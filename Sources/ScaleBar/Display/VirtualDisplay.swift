import Cocoa

final class Virtual {
    let display: CGVirtualDisplay, native: (w: Int, h: Int)
    var stage: Double, real: CGDirectDisplayID, tries = 0, applied = 0, busy = false
    var size: (w: Int, h: Int) { looks(native.w, native.h, stage) }
    init(_ display: CGVirtualDisplay, _ native: (w: Int, h: Int), _ stage: Double, _ real: CGDirectDisplayID) {
        (self.display, self.native, self.stage, self.real) = (display, native, stage, real)
    }
}

extension App {
    // MARK: Virtual displays

    // Every plug/unplug/wake waits 1.5s to settle, so a quick plug-out-and-in or a flapping cable ends in one
    // reconcile against the final state instead of a teardown + rebuild per event.
    func schedule() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }

    // Brings virtual displays in line with the connected monitors and their saved stages. Safe to call any time.
    func reconcile() {
        pending?.cancel()
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        var phys: [String: CGDirectDisplayID] = [:]
        for id in ids.prefix(Int(n)) where CGDisplayVendorNumber(id) != ourVendor && CGDisplayIsBuiltin(id) == 0 { phys[displayKey(id)] = id }

        // DDC talks to "the first external port", so it's only trusted with exactly one external connected.
        // Otherwise keys pass through to macOS and no sliders show. TODO: match ports by EDID to support several.
        externals = phys.count
        singleExternal = phys.count == 1 && pref("ddc") && ddcSupported
        if !singleExternal { ddcValues = [:] }
        for (k, _) in virtuals where phys[k] == nil || saved(k) == nil || !allowVirtual { teardown(k) }
        for (k, id) in phys where allowVirtual {
            guard let s = saved(k) else { continue }
            guard let v = virtuals[k] else { create(k, id, s); continue }
            // Another virtual stage = just a mode switch on the existing virtual display (no rebuild).
            if v.stage != s || v.real != id { (v.stage, v.real, v.tries, v.applied) = (s, id, 0, 0) }
            if !v.busy { mirror(k) }
        }
        refreshDDC()
        updateSettings()
    }

    // Only the 9 known stages are accepted, so a corrupted or edited prefs file can't produce absurd display sizes.
    func saved(_ k: String) -> Double? { (UserDefaults.standard.object(forKey: "virtual." + k) as? Double).flatMap { stages.contains($0) ? $0 : nil } }

    func create(_ k: String, _ real: CGDirectDisplayID, _ s: Double) {
        let ms = modes(real)
        guard let native = nativeMode(ms) else { return }
        let hz = native.refreshRate
        let d = CGVirtualDisplayDescriptor()
        d.setDispatchQueue(.main)
        d.name = screenName(real)
        (d.vendorID, d.productID, d.serialNum) = (ourVendor, CGDisplayModelNumber(real), CGDisplaySerialNumber(real))
        (d.maxPixelsWide, d.maxPixelsHigh) = (UInt32(native.pixelWidth * 2), UInt32(native.pixelHeight * 2)) // the 1x stage
        d.sizeInMillimeters = CGDisplayScreenSize(real)
        d.terminationHandler = { [weak self] _, vd in self?.died(k, vd) }
        let st = CGVirtualDisplaySettings()
        st.hiDPI = 1
        // Every stage up front, so changing stage later is a plain mode switch. Sizes are pixels; hiDPI adds the
        // half-size HiDPI variant of each, which is the one mirror() picks.
        st.modes = stages.map { s in
            let l = looks(native.pixelWidth, native.pixelHeight, s)
            return CGVirtualDisplayMode(width: UInt(l.w * 2), height: UInt(l.h * 2), refreshRate: hz > 0 ? hz : 60)
        }
        UserDefaults.standard.set(true, forKey: "inFlight") // cleared once mirrored (or reverted)
        guard let vd = CGVirtualDisplay(descriptor: d), vd.apply(st) else { return fail(k, "virtual_refused", "macOS refused the virtual display.") }
        virtuals[k] = Virtual(vd, (native.pixelWidth, native.pixelHeight), s, real)
        mirror(k)
    }

    // Set modes, then mirror. Polls every 0.1s (the virtual display takes ~0.5–1s to come online) and re-applies
    // at most once a second. After 5s, give up and revert so the screen is never left in a half state.
    func mirror(_ k: String) {
        guard let v = virtuals[k] else { return }
        let vid = v.display.displayID, size = v.size
        v.busy = false
        let vm = modes(vid).first { $0.width == size.w && $0.pixelWidth == size.w * 2 }
        let modeOK = vm != nil && CGDisplayCopyDisplayMode(vid)?.ioDisplayModeID == vm?.ioDisplayModeID
        let mirrored = CGDisplayMirrorsDisplay(v.real) == vid
        if modeOK && mirrored { v.tries = 0; UserDefaults.standard.removeObject(forKey: "inFlight"); return }
        v.tries += 1
        guard v.tries <= 50 else { return fail(k, "mirror_failed", "Couldn't mirror onto the virtual display.") }
        if let vm, let native = nativeMode(modes(v.real)), v.applied == 0 || v.tries - v.applied >= 10 {
            v.applied = v.tries
            // Two transactions: macOS rejects (1010) modes + mirror combined.
            // Once mirrored, the real display reports the virtual's mode, so leave it alone: re-setting it is a full
            // monitor modeset (screen goes dark). Changing stage then only switches the virtual display's mode.
            let realOK = mirrored || CGDisplayCopyDisplayMode(v.real)?.ioDisplayModeID == native.ioDisplayModeID
            if !modeOK || !realOK {
                configure { cfg in
                    if !modeOK { CGConfigureDisplayWithDisplayMode(cfg, vid, vm, nil) }
                    if !realOK { CGConfigureDisplayWithDisplayMode(cfg, v.real, native, nil) } // native, highest Hz
                }
            }
            if !mirrored { configure { CGConfigureDisplayMirrorOfDisplay($0, v.real, vid) } }
        }
        v.busy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak v] in
            guard let self, let v, self.virtuals[k] === v else { return }
            self.mirror(k)
        }
    }

    func teardown(_ k: String) {
        guard let v = virtuals.removeValue(forKey: k) else { return }
        if CGDisplayMirrorsDisplay(v.real) == v.display.displayID {
            configure { CGConfigureDisplayMirrorOfDisplay($0, v.real, kCGNullDirectDisplay) }
        }
        // Dropping the last reference to the CGVirtualDisplay removes it from the system.
    }

    func fail(_ k: String, _ kind: String, _ msg: String) {
        teardown(k)
        report(kind, monitor: names[k])
        log.error("\(msg, privacy: .public)")
        UserDefaults.standard.removeObject(forKey: "inFlight")
        UserDefaults.standard.removeObject(forKey: "virtual." + k)
        alert(msg + " Reverted to the normal display.")
    }

    // macOS removed our virtual display on its own. Rebuild it, but stop after 3 times per session to avoid a loop.
    func died(_ k: String, _ vd: CGVirtualDisplay?) {
        guard let v = virtuals[k], v.display === vd else { return }
        virtuals[k] = nil
        deaths += 1
        if deaths > 3 { fail(k, "virtual_removed", "macOS keeps removing the virtual display.") } else { schedule() }
    }

    func configure(_ body: (CGDisplayConfigRef?) -> Void) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        body(cfg)
        let r = CGCompleteDisplayConfiguration(cfg, .forSession)
        if r != .success { log.error("display config failed: \(r.rawValue, privacy: .public)"); report("display_config_failed", Int(r.rawValue)); CGCancelDisplayConfiguration(cfg) }
    }
}
