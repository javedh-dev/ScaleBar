import Cocoa
import IOKit

extension App {
    // MARK: Brightness and volume sliders. DDC talks to the physical monitor, so it also works while mirrored.

    // 16 steps, like the macOS brightness and volume keys. The row stays hidden until the monitor reports a value,
    // so controls it doesn't support never appear.
    func ddcItem(_ vcp: UInt8, _ symbol: String, _ name: String) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage())
        icon.frame = NSRect(x: 16, y: 4, width: 20, height: 20)
        let slider = NSSlider(value: 0, minValue: 0, maxValue: 16, target: self, action: #selector(ddcSlide(_:)))
        slider.frame = NSRect(x: 42, y: 2, width: 190, height: 24)
        slider.numberOfTickMarks = 17
        slider.allowsTickMarkValuesOnly = true
        slider.tag = Int(vcp)
        slider.setAccessibilityLabel(name)
        let pct = small("", NSRect(x: 234, y: 6, width: 40, height: 16), 11)
        view.addSubview(icon); view.addSubview(slider); view.addSubview(pct)
        let mi = NSMenuItem(); mi.view = view
        ddcRows[vcp] = (mi, slider, pct)
        updateRow(vcp)
        return mi
    }

    func ddcStep(_ vcp: UInt8) -> Int? { ddcValues[vcp].map { Int((Double($0.cur) * 16 / Double($0.max)).rounded()) } }

    func updateRow(_ vcp: UInt8) {
        guard let row = ddcRows[vcp] else { return }
        row.item.isHidden = ddcValues[vcp] == nil
        guard let step = ddcStep(vcp) else { return }
        row.slider.integerValue = step
        row.pct.stringValue = "\(step * 100 / 16)%"
    }

    @objc func ddcSlide(_ s: NSSlider) { setDDC(UInt8(s.tag), step: s.integerValue) }

    func setDDC(_ vcp: UInt8, step: Int) {
        guard singleExternal, let mx = ddcValues[vcp]?.max else { return }
        let v = Int((Double(min(16, max(0, step))) * Double(mx) / 16).rounded())
        ddcValues[vcp]?.cur = v
        updateRow(vcp)
        let idle = ddcPending[vcp] == nil
        ddcPending[vcp] = v
        if idle { flushDDC(vcp) }
    }

    // One write in flight per control. A drag sends only the latest value, so the monitor isn't flooded.
    func flushDDC(_ vcp: UInt8) {
        guard let v = ddcPending[vcp] else { return }
        ddcQ.async {
            ddcWrite(vcp, v)
            usleep(50_000)
            DispatchQueue.main.async { if self.ddcPending[vcp] == v { self.ddcPending[vcp] = nil } else { self.flushDDC(vcp) } }
        }
    }

    // Reads often fail while the display is switching modes, so a failed read keeps the last good value and
    // retries up to 5 times, 2s apart. Controls the user is dragging are left alone.
    func refreshDDC(attempt: Int = 1) {
        guard singleExternal, attempt > 1 || !ddcChecking else { return }
        ddcChecking = true
        ddcQ.async {
            var r: [UInt8: (cur: Int, max: Int)] = [:]
            for vcp: UInt8 in [0x10, 0x62] { r[vcp] = ddcRead(vcp) }
            DispatchQueue.main.async {
                guard self.singleExternal else { self.ddcChecking = false; return }
                for (vcp, v) in r where self.ddcPending[vcp] == nil { self.ddcValues[vcp] = v; self.updateRow(vcp) }
                if r.isEmpty && attempt < 6 && avService() != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refreshDDC(attempt: attempt + 1) }
                } else {
                    self.ddcChecking = false
                    self.ddcGaveUp = self.ddcValues.isEmpty
                    self.updateSettings()
                }
            }
        }
    }
}

// MARK: DDC/CI over the Apple Silicon AV service (same packets as m1ddc)
// Uses the first external port, which is why DDC is limited to one external monitor (see reconcile).

func avService() -> IOAVService? {
    guard ddcSupported else { return nil }
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    while case let s = IOIteratorNext(it), s != 0 {
        defer { IOObjectRelease(s) }
        let loc = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        if loc == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, s) { return av }
    }
    return nil
}

func ddcChecksum(_ b: [UInt8]) -> UInt8 { b.reduce(0x6E ^ 0x51, ^) }

func ddcWrite(_ vcp: UInt8, _ value: Int) {
    guard let s = avService() else { return }
    var d: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    d.append(ddcChecksum(d))
    _ = IOAVServiceWriteI2C(s, 0x37, 0x51, &d, UInt32(d.count))
}

func ddcRead(_ vcp: UInt8) -> (cur: Int, max: Int)? {
    guard let s = avService() else { return nil }
    for _ in 0..<3 {
        var q: [UInt8] = [0x82, 0x01, vcp]
        q.append(ddcChecksum(q))
        _ = IOAVServiceWriteI2C(s, 0x37, 0x51, &q, UInt32(q.count))
        usleep(50_000)
        var r = [UInt8](repeating: 0, count: 12)
        if IOAVServiceReadI2C(s, 0x37, 0x51, &r, UInt32(r.count)) == KERN_SUCCESS, let v = ddcParse(r, vcp) { return v }
    }
    return nil
}

// Reply: [6E] 88 02 result vcp type maxHi maxLo curHi curLo checksum. Find the 88 02 header, since the
// leading address byte isn't always included.
func ddcParse(_ r: [UInt8], _ vcp: UInt8) -> (cur: Int, max: Int)? {
    guard let i = (0...2).first(where: { r[$0] == 0x88 && r[$0 + 1] == 0x02 }), r[i + 2] == 0, r[i + 3] == vcp else { return nil }
    let mx = Int(r[i + 5]) << 8 | Int(r[i + 6]), cur = Int(r[i + 7]) << 8 | Int(r[i + 8])
    return mx > 0 ? (min(cur, mx), mx) : nil
}
