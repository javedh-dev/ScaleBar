import Cocoa

extension App {
    // MARK: Menu (rebuilt every time it opens, so hot-plugged displays just show up)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        ddcRows = [:]
        if let update {
            menu.addItem(withTitle: "Update available: ScaleBar \(update.version)…", action: #selector(openUpdate), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        let ours = Set(virtuals.values.map { $0.display.displayID })
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        let shown = ids.prefix(Int(n)).filter {
            CGDisplayVendorNumber($0) != ourVendor && CGDisplayIsBuiltin($0) == 0
                && (CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay || ours.contains(CGDisplayMirrorsDisplay($0)))
        }
        let externals = shown.filter { CGDisplayIsBuiltin($0) == 0 }
        for id in shown {
            addDisplay(id, to: menu, ddc: singleExternal && externals == [id])
            if let note = ddcNote(), externals.contains(id), id == externals.last { menu.addItem(info(note)) }
            menu.addItem(.separator())
        }
        if externals.isEmpty { menu.addItem(info("No external display connected")); menu.addItem(.separator()) }
        refreshDDC()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func addDisplay(_ id: CGDirectDisplayID, to menu: NSMenu, ddc: Bool) {
        guard let native = virtuals[displayKey(id)]?.panel ?? nativeMode(modes(id)), let cur = CGDisplayCopyDisplayMode(id) else { return }
        let v = virtuals[displayKey(id)]
        menu.addItem(.sectionHeader(title: screenName(id)))

        // A row of boxes, one per scale, the current one selected. The resolution each gives is in its tooltip.
        let avail = v?.avail ?? stages(forWidth: native.pixelWidth, mm: CGDisplayScreenSize(id).width) // see reconcile()
        let current = v?.stage ?? (Double(native.pixelWidth) / Double(cur.width) * 4).rounded() / 4
        let seg = NSSegmentedControl(labels: avail.map { "\($0.formatted())x" }, trackingMode: .selectOne, target: self, action: #selector(pick(_:)))
        (seg.controlSize, seg.font, seg.segmentDistribution, seg.tag) = (.small, .monospacedDigitSystemFont(ofSize: 10, weight: .regular), .fillEqually, Int(id))
        seg.frame = NSRect(x: 16, y: 4, width: 248, height: 22)
        seg.setAccessibilityLabel("Scale")
        for (i, s) in avail.enumerated() {
            let (_, text, ok) = scaleOption(id, s)
            seg.setToolTip(text, forSegment: i)
            seg.setEnabled(ok, forSegment: i)
            seg.setSelected(s == current, forSegment: i)
            seg.setTag(Int(s * 100), forSegment: i) // stages are multiples of 0.25, so this is exact
        }
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 30))
        view.addSubview(seg)
        let mi = NSMenuItem(); mi.view = view
        menu.addItem(mi)

        guard CGDisplayIsBuiltin(id) == 0 else { return }
        if ddc {
            for (vcp, symbol, name) in [(UInt8(0x10), "sun.max", "Brightness"), (0x62, "speaker.wave.2", "Volume")] {
                menu.addItem(ddcItem(vcp, symbol, name))
            }
        }
    }

    // Explains why the brightness and volume rows are missing. nil when there's nothing to explain.
    func ddcNote() -> String? {
        guard pref("ddc"), externals > 0 else { return nil }
        if !ddcSupported || avService() == nil { return "Brightness & volume: not supported on this Mac or port" }
        if externals > 1 { return "Brightness & volume: one external monitor at a time" }
        if ddcValues.isEmpty && ddcGaveUp { return "Brightness & volume: monitor didn't respond (turn on DDC/CI)" }
        return nil
    }

    func info(_ text: String) -> NSMenuItem {
        let mi = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        mi.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        mi.isEnabled = false
        return mi
    }

    var allowVirtual: Bool { virtualSupported && pref("virtualDisplay") }

    func describe(_ m: CGDisplayMode) -> String {
        "\(m.width)×\(m.height)" + (m.pixelWidth > m.width ? " HiDPI" : "") + (m.refreshRate > 0 ? " · \(Int(m.refreshRate.rounded()))Hz" : "")
    }

    func virtualLabel(_ native: CGDisplayMode, _ s: Double) -> String {
        let l = looks(native.pixelWidth, native.pixelHeight, s)
        return "\(l.w)×\(l.h) HiDPI · virtual · \(Int(native.refreshRate.rounded()))Hz"
    }

    func small(_ text: String, _ frame: NSRect, _ size: CGFloat, _ align: NSTextAlignment = .natural) -> NSTextField {
        let t = NSTextField(labelWithString: text)
        t.frame = frame; t.alignment = align; t.lineBreakMode = .byTruncatingTail
        t.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular); t.textColor = .secondaryLabelColor
        return t
    }

    // Real mode whose looks-like size is native/s (rounding to even drifts the ratio by < 0.02 stages).
    // 1x = the native 1x mode. Every other stage must be HiDPI: a 1x mode below native is just blurry.
    func mode(_ id: CGDirectDisplayID, scale s: Double) -> CGDisplayMode? {
        let ms = modes(id)
        guard let native = nativeMode(ms) else { return nil }
        let fits = { (n: Int, looks: Int) in abs(Double(n) / Double(looks) - s) * 4 < 0.03 }
        return ms.filter { fits(native.pixelWidth, $0.width) && fits(native.pixelHeight, $0.height) && ($0.pixelWidth > $0.width) == (s != 1) }
            .max { $0.refreshRate < $1.refreshRate }
    }

    // What scale s does on display id: the real mode it uses (nil = virtual display), a description, and whether it can be picked.
    func scaleOption(_ id: CGDirectDisplayID, _ s: Double) -> (real: CGDisplayMode?, text: String, ok: Bool) {
        let v = virtuals[displayKey(id)]
        guard let native = v?.panel ?? nativeMode(modes(id)) else { return (nil, "", false) }
        // While mirrored the panel lists the virtual display's modes, not its own, so real modes can't be looked up.
        if let v { return (nil, s == 1 ? describe(v.panel) : virtualLabel(native, s), true) }
        if let real = mode(id, scale: s) { return (real, describe(real), true) }
        if CGDisplayIsBuiltin(id) != 0 { return (nil, "not available on this display", false) }
        if allowVirtual { return (nil, virtualLabel(native, s), true) }
        return (nil, virtualSupported ? "needs the virtual display (off in Settings)" : "needs a virtual display (not supported on this macOS)", false)
    }

    @objc func pick(_ seg: NSSegmentedControl) {
        let id = CGDirectDisplayID(seg.tag), k = displayKey(id)
        guard seg.selectedSegment >= 0 else { return }
        let s = Double(seg.tag(forSegment: seg.selectedSegment)) / 100
        let (real, _, ok) = scaleOption(id, s)
        guard ok else { return }
        // cancelTracking only asks the menu to close; it's gone once the run loop is back in default mode. Switching
        // modes under a still-open menu leaves it drawn at the old screen geometry.
        item.menu?.cancelTracking()
        RunLoop.main.perform(inModes: [.default]) { [self] in
            if let real {
                UserDefaults.standard.removeObject(forKey: "virtual." + k)
                teardown(k)
                if real.ioDisplayModeID != CGDisplayCopyDisplayMode(id)?.ioDisplayModeID { configure { CGConfigureDisplayWithDisplayMode($0, id, real, nil) } }
            } else if virtuals[k] != nil && s == 1 {
                UserDefaults.standard.removeObject(forKey: "virtual." + k)
                teardown(k) // also puts the panel back on native
                reconcile()
            } else {
                UserDefaults.standard.set(s, forKey: "virtual." + k)
                reconcile()
            }
        }
    }
}
