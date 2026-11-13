import Cocoa
import os

let log = Logger(subsystem: "local.scalebar", category: "app") // errors only; keys and user activity are never logged

let ourVendor: UInt32 = 0x5342 // "SB": marks our virtual displays

// Survives re-plugs (display IDs can change). TODO: two identical monitors without serial numbers share a key.
func displayKey(_ id: CGDirectDisplayID) -> String {
    "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
}

// Looks-like size for a stage, rounded to even.
func looks(_ w: Int, _ h: Int, _ s: Double) -> (w: Int, h: Int) {
    (Int((Double(w) / s / 2).rounded()) * 2, Int((Double(h) / s / 2).rounded()) * 2)
}

let stages = Array(stride(from: 1.0, through: 3.0, by: 0.25))
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

// All settings default to on.
func pref(_ k: String) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? true }

// Private APIs are weak-imported (ScaleBar-Bridging-Header.h). Check they exist before use, so a future macOS that drops them
// gets a clear "not supported" instead of a crash.
let virtualSupported = ["CGVirtualDisplay", "CGVirtualDisplayDescriptor", "CGVirtualDisplaySettings", "CGVirtualDisplayMode"]
    .allSatisfy { NSClassFromString($0) != nil }
    && (NSClassFromString("CGVirtualDisplay") as? NSObject.Type)?.instancesRespond(to: NSSelectorFromString("applySettings:")) == true
    && (NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type)?.instancesRespond(to: NSSelectorFromString("setDispatchQueue:")) == true
let ddcSupported: Bool = {
    let names: [String] = ["IOAVServiceCreateWithService", "IOAVServiceReadI2C", "IOAVServiceWriteI2C"]
    return names.allSatisfy { dlsym(UnsafeMutableRawPointer(bitPattern: -2), $0) != nil } // -2 = RTLD_DEFAULT
}()

// Dotted version compare: "1.10" > "1.9", "1.0" == "1.0.0".
func newer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}
