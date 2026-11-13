import Cocoa

extension App {
    // MARK: Menu (rebuilt every time it opens, so hot-plugged displays just show up)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        labels = [:]
        ddcRows = [:]
        if let update {
            menu.addItem(withTitle: "Update available: ScaleBar \(update.version)…", action: #selector(openUpdate), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        let ours = Set(virtuals.values.map { $0.display.displayID })
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        let shown = ids.prefix(Int(n)).filter {
            CGDisplayVendorNumber($0) != ourVendor
                && (CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay || ours.contains(CGDisplayMirrorsDisplay($0)))
        }
        let externals = shown.filter { CGDisplayIsBuiltin($0) == 0 }
        for id in shown {
            addDisplay(id, to: menu, ddc: singleExternal && externals == [id])
            if let note = ddcNote(), externals.contains(id), id == externals.last { menu.addItem(info(note)) }
            menu.addItem(.separator())
        }
        refreshDDC()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "About ScaleBar", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func addDisplay(_ id: CGDirectDisplayID, to menu: NSMenu, ddc: Bool) {
        guard let native = nativeMode(modes(id)), let cur = CGDisplayCopyDisplayMode(id) else { return }
        let v = virtuals[displayKey(id)]
        menu.addItem(.sectionHeader(title: screenName(id)))

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 58))
        let icon = NSImageView(image: NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Scale") ?? NSImage())
        icon.frame = NSRect(x: 16, y: 18, width: 20, height: 20)
        let slider = NSSlider(value: 1, minValue: 1, maxValue: 3, target: self, action: #selector(slide(_:)))
        slider.frame = NSRect(x: 42, y: 16, width: 190, height: 24)
        slider.numberOfTickMarks = 9
        slider.allowsTickMarkValuesOnly = true
        slider.tag = Int(id)
        slider.doubleValue = v?.stage ?? (Double(native.pixelWidth) / Double(cur.width) * 4).rounded() / 4
        slider.setAccessibilityLabel("Scale")
        let value = small("\(slider.doubleValue.formatted())x", NSRect(x: 234, y: 20, width: 40, height: 16), 11)
        let detail = small(v.map { virtualLabel(native, $0.stage) } ?? describe(cur), NSRect(x: 42, y: 42, width: 232, height: 14), 10)
        for i in stride(from: 0, to: 9, by: 4) { // captions under 1x, 2x, 3x
            view.addSubview(small("\(stages[i].formatted())x", NSRect(x: slider.frame.minX + slider.rectOfTickMark(at: i).midX - 15, y: 3, width: 30, height: 12), 9, .center))
        }
        [icon, slider, value, detail].forEach(view.addSubview)
        labels[id] = (value, detail)
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

    // Live label while dragging; switch only on release.
    @objc func slide(_ slider: NSSlider) {
        let id = CGDirectDisplayID(slider.tag), s = slider.doubleValue, k = displayKey(id)
        guard let native = nativeMode(modes(id)) else { return }
        let real = mode(id, scale: s), ext = CGDisplayIsBuiltin(id) == 0
        labels[id]?.value.stringValue = "\(s.formatted())x"
        labels[id]?.detail.stringValue = real.map(describe) ?? (!ext ? "not available on this display"
            : allowVirtual ? virtualLabel(native, s)
            : virtualSupported ? "needs the virtual display (off in Settings)" : "needs a virtual display (not supported on this macOS)")
        guard NSApp.currentEvent?.type == .leftMouseUp else { return }
        if let real {
            UserDefaults.standard.removeObject(forKey: "virtual." + k)
            teardown(k)
            if real.ioDisplayModeID != CGDisplayCopyDisplayMode(id)?.ioDisplayModeID { configure { CGConfigureDisplayWithDisplayMode($0, id, real, nil) } }
        } else if ext && allowVirtual {
            UserDefaults.standard.set(s, forKey: "virtual." + k)
            reconcile()
        }
    }
}
