import Cocoa

// `ScaleBar --selftest`: checks the pure logic without touching any display.
if CommandLine.arguments.contains("--selftest") {
    precondition(looks(2560, 1440, 1.5) == (1706, 960) && looks(2560, 1440, 1) == (2560, 1440) && looks(2560, 1440, 1.75) == (1462, 822))
    precondition(stages(forWidth: 3840, mm: 531).last == 3 && stages(forWidth: 2560, mm: 708).last == 1.5 && stages(forWidth: 2560, mm: 597).last == 1.75)
    precondition(stages(forWidth: 3840, mm: 0).last == 3 && stages(forWidth: 2560, mm: 0).last == 2 && stages(forWidth: 1024, mm: 0) == [1])
    precondition(ddcChecksum([0x82, 0x01, 0x10]) == 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10)
    let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
    precondition(ddcParse(reply, 0x10)! == (50, 100) && ddcParse(Array(reply.dropFirst()) + [0], 0x10)! == (50, 100))
    precondition(newer("1.10", than: "1.9") && newer("2", than: "1.9.9") && !newer("1.0", than: "1.0.0") && !newer("1.0", than: "1.1"))
    precondition(ddcParse(reply, 0x62) == nil && ddcParse([UInt8](repeating: 0, count: 12), 0x10) == nil)
    let t = tmSign(key: "k_test", secret: "tm_sk_test_secret", ts: "1763020800", body: Data(#"{"events":[{"name":"active"}]}"#.utf8), bits: 8, start: 0)
    precondition(t.nonce == "352" && t.sig == "0000ac2a046f0231aabd836642ad818b64f1f9815bb31ae385a96df119407735")
    print("selftest ok")
    exit(0)
}

// `ScaleBar --make-iconset <dir>`: build.sh turns this into AppIcon.icns.
if let i = CommandLine.arguments.firstIndex(of: "--make-iconset"), i + 1 < CommandLine.arguments.count {
    let dir = CommandLine.arguments[i + 1]
    for (pt, scale) in [16, 32, 128, 256, 512].flatMap({ [($0, 1), ($0, 2)] }) {
        let name = "icon_\(pt)x\(pt)" + (scale == 2 ? "@2x" : "") + ".png"
        guard (try? appIcon(pt * scale)?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))) != nil else { exit(1) }
    }
    exit(0)
}

let app = NSApplication.shared
let appDelegate = App()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
