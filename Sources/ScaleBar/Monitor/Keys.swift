import Cocoa
import CoreAudio

extension App {
    // MARK: Keyboard brightness / volume keys + on-screen HUD

    // Needs Accessibility permission. Asks once, then checks every 3s until it's granted.
    func startKeyTap() {
        guard pref("keys"), keyTap == nil else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): !askedAX] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        askedAX = true
        guard trusted else {
            if !axPolling {
                axPolling = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.axPolling = false; self?.startKeyTap() }
            }
            return updateSettings()
        }
        keyTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                   eventsOfInterest: CGEventMask(1 << 14 | 1 << 10 | 1 << 11), callback: { _, type, event, _ in
            // Privacy: every other key passes straight through and is never stored or logged.
            // Brightness arrives either as a media key (codes 2/3) or, on many keyboards, as a plain key:
            // 144/145 (Apple brightness up/down) or F15/F14 (macOS's brightness keys on PC keyboards).
            let plain: [Int64: Int] = [144: 2, 145: 3, 113: 2, 107: 3]
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = appDelegate.keyTap { CGEvent.tapEnable(tap: t, enable: true) }
            } else if type.rawValue == 14, let e = NSEvent(cgEvent: event), e.subtype.rawValue == 8,
                      appDelegate.mediaKey(e.data1 >> 16 & 0xFFFF, down: e.data1 >> 8 & 0xFF == 0x0A) {
                return nil // swallow it so macOS doesn't act on it too
            } else if type == .keyDown || type == .keyUp, let code = plain[event.getIntegerValueField(.keyboardEventKeycode)],
                      appDelegate.mediaKey(code, down: type == .keyDown) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: nil)
        guard let keyTap else { log.error("key tap could not be created"); return updateSettings() }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, keyTap, 0), .commonModes)
        updateSettings()
    }

    func stopKeyTap() {
        if let t = keyTap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        keyTap = nil
    }

    // Brightness keys drive the monitor when no built-in screen is on (lid closed); volume keys when sound goes to
    // the monitor. Otherwise the keys pass through to macOS untouched.
    func mediaKey(_ code: Int, down: Bool) -> Bool {
        let keys: [Int: (vcp: UInt8, delta: Int)] = [0: (0x62, 1), 1: (0x62, -1), 7: (0x62, 0), 2: (0x10, 1), 3: (0x10, -1)]
        guard let (vcp, delta) = keys[code], var step = ddcStep(vcp), vcp == 0x10 ? !builtinActive() : soundOnMonitor() else { return false }
        guard down else { return true }
        if delta == 0 { (step, muted[vcp]) = step > 0 ? (0, step) : (muted[vcp] ?? 8, nil) } else { step = min(16, max(0, step + delta)) }
        setDDC(vcp, step: step)
        showHUD(vcp == 0x10 ? "sun.max.fill" : step == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", step)
        return true
    }

    func builtinActive() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).contains { CGDisplayIsBuiltin($0) != 0 }
    }

    func soundOnMonitor() -> Bool {
        var dev = AudioObjectID(0), t: UInt32 = 0, size = UInt32(4)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr else { return false }
        a.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &t) == noErr else { return false }
        return t == kAudioDeviceTransportTypeDisplayPort || t == kAudioDeviceTransportTypeHDMI
    }

    // On-screen popup like macOS's own: icon and 16 segments, fades out after about a second.
    func showHUD(_ symbol: String, _ step: Int) {
        let p = hud ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            (p.level, p.isOpaque, p.backgroundColor, p.ignoresMouseEvents) = (.statusBar, false, .clear, true)
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let fx = NSVisualEffectView(frame: p.contentView!.bounds)
            (fx.material, fx.state, fx.wantsLayer) = (.hudWindow, .active, true)
            fx.layer?.cornerRadius = 18
            p.contentView = fx
            hud = p
            return p
        }()
        guard let fx = p.contentView else { return }
        fx.subviews.forEach { $0.removeFromSuperview() }
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 72, weight: .regular)) ?? NSImage())
        icon.frame = NSRect(x: 40, y: 50, width: 120, height: 120)
        icon.contentTintColor = .labelColor
        fx.addSubview(icon)
        for i in 0..<16 {
            let seg = NSView(frame: NSRect(x: 20 + i * 10, y: 24, width: 9, height: 7))
            seg.wantsLayer = true
            seg.layer?.backgroundColor = (i < step ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.2)).cgColor
            fx.addSubview(seg)
        }
        if let sc = NSScreen.main?.frame { p.setFrameOrigin(NSPoint(x: sc.midX - 100, y: sc.minY + 140)) }
        NSAnimationContext.runAnimationGroup { $0.duration = 0; p.animator().alphaValue = 1 } // cancels a fade in progress
        p.orderFrontRegardless()
        hudHide?.cancel()
        var w: DispatchWorkItem!
        w = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) { if self?.hudHide === w { p.orderOut(nil) } }
        }
        hudHide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }
}
