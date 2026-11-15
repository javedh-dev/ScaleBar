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
        func text(_ s: String, _ size: CGFloat, _ color: NSColor = .labelColor, weight: NSFont.Weight = .regular) -> NSTextField {
            let t = NSTextField(wrappingLabelWithString: s)
            (t.font, t.textColor, t.preferredMaxLayoutWidth) = (.systemFont(ofSize: size, weight: weight), color, 300)
            return t
        }
        func stack(_ views: [NSView], _ spacing: CGFloat, vertical: Bool = true) -> NSStackView {
            let v = NSStackView(views: views)
            (v.orientation, v.alignment, v.spacing) = vertical ? (.vertical, .leading, spacing) : (.horizontal, .centerY, spacing)
            return v
        }
        func button(_ title: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: sel)
            (b.bezelStyle, b.controlSize) = (.rounded, .small)
            return b
        }
        // A checkbox bound to a pref. The explanation is a tooltip; the line under it only appears for problems.
        func option(_ title: String, _ key: String, help: String, trailing: [NSView] = [], below: [NSView] = []) -> NSView {
            let cb = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
            (cb.identifier, cb.state, cb.toolTip) = (NSUserInterfaceItemIdentifier(key), pref(key) ? .on : .off, help)
            let note = text("", 11, .secondaryLabelColor)
            status[key] = note
            let indented = stack([note] + below, 4)
            indented.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0) // lines up with the checkbox title
            return stack([stack([cb] + trailing, 8, vertical: false), indented], 2)
        }
        let section = { (s: String) in text(s, 11, .secondaryLabelColor, weight: .semibold) }

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let header = stack([icon, stack([text("ScaleBar", 15, weight: .semibold), text("Version \(appVersion)", 11, .secondaryLabelColor)], 1)], 10, vertical: false)

        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin(_:)))
        loginBox = login
        let loginNote = text("", 11, .secondaryLabelColor)
        status["login"] = loginNote
        let loginIndented = stack([loginNote], 0)
        loginIndented.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        axButton = button("Open Accessibility Settings…", #selector(openAccessibility))

        let about = NSButton(title: "About ScaleBar", target: self, action: #selector(showAbout))
        (about.isBordered, about.font, about.contentTintColor) = (false, .systemFont(ofSize: 11), .linkColor)

        let general = stack([
            option("Show this window at startup", "showSettingsAtLaunch", help: "You can always open Settings from the menu bar icon."),
            stack([login, loginIndented], 2),
            option("Check for updates automatically", "autoUpdate", help: "Checks GitHub once a day. Nothing is downloaded or installed automatically.",
                   trailing: [button("Check Now", #selector(checkNow))]),
            option("Help improve ScaleBar by sharing diagnostics", "telemetry", help: telemetryExplainer,
                   below: [text("A daily anonymous active count (app version only) is always sent. Hover for details.", 11, .secondaryLabelColor), button("Privacy Policy…", #selector(openPrivacy))]),
        ], 8)
        let monitor = stack([
            option("Virtual display for in-between scales", "virtualDisplay",
                   help: "Gives sharp HiDPI at sizes the monitor doesn't offer (e.g. 1.5x on 1440p). The screen blanks briefly when switching in or out."),
            option("Brightness and volume control", "ddc", help: "Controls the external monitor over DDC/CI. Needs DDC/CI turned on in the monitor's own menu."),
            option("Brightness and volume keys", "keys", help: "Brightness keys work while the Mac's screen is off; volume keys while sound plays through the monitor. No other keys are read.",
                   below: [axButton!]),
        ], 8)

        let reset = button("Reset Scaling to Default…", #selector(resetScaling))
        reset.toolTip = "Puts every external monitor back on its native resolution and forgets saved scales."
        let content = stack([header, section("General"), general, section("Monitor"), monitor, reset, about], 10)
        content.setCustomSpacing(20, after: header)
        content.setCustomSpacing(20, after: general)
        content.setCustomSpacing(22, after: monitor)
        content.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 16, right: 22)
        content.widthAnchor.constraint(equalToConstant: 380).isActive = true
        w.contentView = content
        w.center()
        return w
    }

    // Refreshes the problem lines; cheap, so it's called whenever anything changes.
    func updateSettings() {
        guard let w = settings else { return }
        // Hides an empty note, and its indented row when nothing in it is visible.
        func set(_ k: String, _ s: String) {
            guard let note = status[k] else { return }
            (note.stringValue, note.isHidden) = (s, s.isEmpty)
            if let row = note.superview as? NSStackView { row.isHidden = row.arrangedSubviews.allSatisfy(\.isHidden) }
        }
        axButton?.isHidden = !(pref("keys") && !AXIsProcessTrusted())
        set("virtualDisplay", virtualSupported ? "" : "Not supported on this version of macOS.")
        set("ddc", ddcStatus())
        set("keys", keysStatus())
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

    // Empty when everything is fine or the feature is off; otherwise a short reason.
    func ddcStatus() -> String {
        guard pref("ddc"), externals > 0 else { return "" }
        if !ddcSupported || avService() == nil { return "Not available on this Mac or port. Needs Apple Silicon; some HDMI ports and docks block it." }
        if externals > 1 { return "Works with one external monitor at a time." }
        if ddcValues.isEmpty { return ddcGaveUp ? "The monitor didn't respond. Turn on DDC/CI in its on-screen menu." : "" }
        if ddcValues[0x10] == nil { return "This monitor doesn't support brightness control." }
        if ddcValues[0x62] == nil { return "This monitor doesn't support volume control." }
        return ""
    }

    func keysStatus() -> String {
        guard pref("keys") else { return "" }
        if !pref("ddc") { return "Needs brightness and volume control turned on." }
        if !AXIsProcessTrusted() { return "Needs Accessibility permission." }
        if keyTap == nil { return "Couldn't listen to the keyboard. Quit and reopen ScaleBar." }
        return ""
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

    // Built-in display is never touched: only externals are reset.
    @objc func resetScaling() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Reset scaling to default?"
        a.informativeText = "Every external monitor goes back to its native resolution and saved scales are forgotten."
        a.addButton(withTitle: "Reset"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("virtual.") }.forEach(UserDefaults.standard.removeObject)
        virtuals.keys.forEach(teardown) // also puts those panels back on native
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        for id in ids.prefix(Int(n)) where CGDisplayVendorNumber(id) != ourVendor && CGDisplayIsBuiltin(id) == 0 {
            if let native = nativeMode(modes(id)), native.ioDisplayModeID != CGDisplayCopyDisplayMode(id)?.ioDisplayModeID {
                configure { CGConfigureDisplayWithDisplayMode($0, id, native, nil) }
            }
        }
        reconcile()
    }

    @objc func openPrivacy() { NSWorkspace.shared.open(privacyURL) }

    @objc func toggleLogin(_ b: NSButton) {
        do {
            if b.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch {
            loginError = "Couldn't change it. Moving ScaleBar to Applications usually helps."
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
            .credits: NSAttributedString(string: "Sharp display scaling, brightness and volume for macOS.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
}
