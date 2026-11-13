import Cocoa

// One slider per display: scale 1x–3x in 0.25 stages. Scale = native width / looks-like width.
// A stage uses a real mode when the display has one (1x native, plus macOS's own HiDPI sizes such as 2x).
// Otherwise (externals only) it uses a virtual HiDPI display that the real display mirrors. macOS on Apple Silicon
// ignores HiDPI override plists, so this is the only way to get e.g. 1.5x HiDPI on a 1440p panel.
// Only 1x and 2x map pixels 1:1. The other stages are HiDPI-supersampled (above 2x the GPU upscales).
//
// Failsafe: the virtual display belongs to this process. If ScaleBar quits or crashes, macOS removes it and the
// real display goes back to normal. Mirroring is applied .forSession only, so nothing sticks past logout.

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var labels: [CGDirectDisplayID: (value: NSTextField, detail: NSTextField)] = [:]
    var virtuals: [String: Virtual] = [:]
    var names: [String: String] = [:]
    var pending: DispatchWorkItem?
    var deaths = 0
    let ddcQ = DispatchQueue(label: "ddc")
    var ddcValues: [UInt8: (cur: Int, max: Int)] = [:]
    var ddcPending: [UInt8: Int] = [:]
    var ddcRows: [UInt8: (item: NSMenuItem, slider: NSSlider, pct: NSTextField)] = [:]
    var muted: [UInt8: Int] = [:]
    var singleExternal = false // DDC is usable: turned on, supported, and exactly one external monitor
    var externals = 0
    var ddcChecking = false, ddcGaveUp = false
    var axPolling = false
    var keyTap: CFMachPort?
    var askedAX = false
    var hud: NSPanel?
    var hudHide: DispatchWorkItem?

    func applicationDidFinishLaunching(_: Notification) {
        item.button?.image = menuBarIcon()
        item.menu = NSMenu()
        item.menu!.delegate = self
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard !flags.contains(.beginConfigurationFlag),
                  !flags.isDisjoint(with: [.addFlag, .removeFlag, .enabledFlag, .disabledFlag]) else { return }
            DispatchQueue.main.async { appDelegate.schedule() }
        }, nil)
        for n in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.schedule() }
        }
        // If the last run died while setting up a virtual display (e.g. the private API changed in a macOS update),
        // start in normal mode instead of crashing the same way on every launch.
        if UserDefaults.standard.bool(forKey: "inFlight") {
            UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("virtual.") }.forEach(UserDefaults.standard.removeObject)
            UserDefaults.standard.removeObject(forKey: "inFlight")
            alert("ScaleBar stopped unexpectedly while setting up the virtual display last time, so it started in normal mode.")
        }
        reconcile()
        startKeyTap()
        if pref("showSettingsAtLaunch") { showSettings() }
        // Runs hourly, but autoCheck() contacts GitHub at most once a day.
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.autoCheck() }.fire()
    }

    func applicationWillTerminate(_: Notification) { virtuals.keys.forEach(teardown) }

    // State for the other files. Swift extensions can't hold stored properties, so it lives here.
    var settings: NSWindow?
    var status: [String: NSTextField] = [:]
    var axButton: NSButton?, loginBox: NSButton?
    var loginError = "", updateText = ""
    var update: (version: String, url: URL)?

    func alert(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = text; a.runModal()
    }
}

extension App {
    // MARK: Display helpers

    func modes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
    }

    // Native panel size = the largest 1x mode, at its highest refresh rate.
    func nativeMode(_ modes: [CGDisplayMode]) -> CGDisplayMode? {
        modes.filter { $0.pixelWidth == $0.width }.max { ($0.pixelWidth, $0.refreshRate) < ($1.pixelWidth, $1.refreshRate) }
    }

    // A display that mirrors has no NSScreen, so remember names from when it did.
    func screenName(_ id: CGDirectDisplayID) -> String {
        let k = displayKey(id)
        if let n = NSScreen.screens.first(where: { ($0.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID) == id })?.localizedName {
            names[k] = n.replacingOccurrences(of: " (ScaleBar HiDPI)", with: "")
        }
        return names[k] ?? "Display \(id)"
    }
}
