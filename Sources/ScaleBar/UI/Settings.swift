import Cocoa
import ServiceManagement

extension App {
    // MARK: Settings & About


    @objc func showSettings() {
        if settings == nil { settings = makeSettings() }
        updateSettings()
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    func makeSettings() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "ScaleBar Settings"
        w.isReleasedWhenClosed = false
        func text(_ s: String, _ size: CGFloat, _ color: NSColor = .labelColor, bold: Bool = false) -> NSTextField {
            let t = NSTextField(wrappingLabelWithString: s)
            t.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
            t.textColor = color
            t.preferredMaxLayoutWidth = 340
            return t
        }
        func vstack(_ views: [NSView], _ spacing: CGFloat) -> NSStackView {
            let v = NSStackView(views: views)
            (v.orientation, v.alignment, v.spacing) = (.vertical, .leading, spacing)
            return v
        }
        // A checkbox bound to a pref, with a live status line under it.
        func option(_ title: String, _ key: String, extra: [NSView] = []) -> NSView {
            let cb = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
            cb.identifier = NSUserInterfaceItemIdentifier(key)
            cb.state = pref(key) ? .on : .off
            let st = text("", 11, .secondaryLabelColor)
            status[key] = st
            return vstack([cb, st] + extra, 3)
        }
        func button(_ title: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: sel)
            (b.bezelStyle, b.controlSize) = (.rounded, .small)
            return b
        }
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let header = NSStackView(views: [icon, vstack([text("ScaleBar", 17, bold: true),
                                                       text("Version \(appVersion) · Made by \(author)", 11, .secondaryLabelColor)], 2)])
        header.spacing = 12

        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin(_:)))
        loginBox = login
        let loginStatus = text("", 11, .secondaryLabelColor)
        status["login"] = loginStatus
        axButton = button("Open Accessibility Settings…", #selector(openAccessibility))

        let section = { (s: String) in text(s.uppercased(), 10, .tertiaryLabelColor, bold: true) }
        let stack = vstack([
            header,
            section("General"),
            option("Show this window when ScaleBar starts", "showSettingsAtLaunch"),
            vstack([login, loginStatus], 3),
            section("Display"),
            option("Use a virtual display for in-between scales", "virtualDisplay"),
            section("Monitor control"),
            option("Brightness & volume sliders (DDC/CI)", "ddc"),
            option("Keyboard brightness & volume keys control the monitor", "keys", extra: [axButton!]),
            section("Updates"),
            option("Check for updates automatically", "autoUpdate", extra: [button("Check Now", #selector(checkNow))]),
            button("About ScaleBar", #selector(showAbout)),
        ], 10)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(18, after: header)
        stack.widthAnchor.constraint(equalToConstant: 400).isActive = true
        w.contentView = stack
        w.center()
        return w
    }

    // Refreshes every status line; cheap, so it's called whenever anything changes.
    func updateSettings() {
        guard let w = settings else { return }
        func set(_ k: String, _ s: String) { status[k]?.stringValue = s; status[k]?.isHidden = s.isEmpty }
        set("virtualDisplay", !virtualSupported ? "⚠︎ Not supported on this version of macOS. Only the display's own modes are offered."
            : pref("virtualDisplay") ? "Scales the display doesn't offer itself (e.g. 1.25x, 1.5x on a 1440p monitor) use a mirrored virtual HiDPI display. The screen blanks briefly when switching in or out."
            : "Off: only the display's own modes are offered.")
        set("ddc", ddcStatus())
        set("keys", keysStatus())
        axButton?.isHidden = !(pref("keys") && !AXIsProcessTrusted())
        set("autoUpdate", updateText)
        let ls = SMAppService.mainApp.status
        loginBox?.state = ls == .enabled ? .on : .off
        set("login", !loginError.isEmpty ? loginError : ls == .requiresApproval ? "Needs approval in System Settings → General → Login Items." : "")
        if let v = w.contentView {
            let top = w.frame.maxY
            v.layoutSubtreeIfNeeded()
            w.setContentSize(v.fittingSize)
            w.setFrameTopLeftPoint(NSPoint(x: w.frame.minX, y: top))
        }
    }

    func ddcStatus() -> String {
        guard pref("ddc") else { return "Off." }
        guard ddcSupported else { return "⚠︎ Not supported on this version of macOS." }
        if externals == 0 { return "Connect an external monitor to control its brightness and volume." }
        if avService() == nil { return "⚠︎ Can't reach the monitor's controls from this Mac or port. Needs Apple Silicon; some built-in HDMI ports and docks don't pass DDC/CI." }
        if externals > 1 { return "⚠︎ Works with one external monitor at a time." }
        if ddcValues.isEmpty { return ddcGaveUp ? "⚠︎ The monitor didn't respond. Turn on DDC/CI in its on-screen menu. Some docks and adapters block it." : "Checking the monitor…" }
        return "Monitor: " + (ddcValues[0x10] != nil ? "brightness ✓" : "brightness not supported") + ", "
            + (ddcValues[0x62] != nil ? "volume ✓" : "volume not supported (no speakers?)") + "."
    }

    func keysStatus() -> String {
        guard pref("keys") else { return "Off: the keys control the Mac as usual." }
        if !pref("ddc") { return "⚠︎ Needs \"Brightness & volume sliders\" turned on." }
        if !AXIsProcessTrusted() { return "⚠︎ Needs Accessibility permission to see the brightness and volume keys." }
        if keyTap == nil { return "⚠︎ Couldn't listen to the keyboard. Quit and reopen ScaleBar." }
        return "Brightness keys control the monitor while the Mac's own screen is off; volume keys while sound plays through the monitor. No other keys are read."
    }

    @objc func toggle(_ b: NSButton) {
        guard let k = b.identifier?.rawValue else { return }
        UserDefaults.standard.set(b.state == .on, forKey: k)
        switch k {
        case "virtualDisplay": reconcile()
        case "ddc": (ddcValues, ddcGaveUp) = ([:], false); reconcile()
        case "keys": if b.state == .on { startKeyTap() } else { stopKeyTap() }
        case "autoUpdate": if b.state == .on { checkForUpdates(manual: false) }
        default: break
        }
        updateSettings()
    }

    @objc func toggleLogin(_ b: NSButton) {
        do {
            if b.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch {
            loginError = "⚠︎ Couldn't change it: \(error.localizedDescription) Moving ScaleBar to /Applications usually helps."
        }
        updateSettings()
    }

    @objc func openAccessibility() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ScaleBar",
            .credits: NSAttributedString(string: "Made by \(author)\nSharp display scaling, brightness and volume for macOS.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
}
