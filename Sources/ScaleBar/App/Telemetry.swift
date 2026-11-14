import Cocoa
import CryptoKit
import ServiceManagement

// Zero bits at the start of a SHA-256 digest.
func zeroBits(_ d: SHA256.Digest) -> Int {
    var n = 0
    for b in d { if b == 0 { n += 8 } else { return n + b.leadingZeroBitCount } }
    return n
}

// tallymoth signed request: finds a nonce (from `start`) whose hash has `bits` zero bits, then HMACs the message.
// See https://javedh-dev.github.io/tallymoth/signing
func tmSign(key: String, secret: String, ts: String, body: Data, bits: Int, start: UInt64) -> (nonce: String, sig: String) {
    var n = start
    while true {
        let msg = Data("v1.\(key).\(ts).\(n).".utf8) + body
        if zeroBits(SHA256.hash(data: msg)) >= bits {
            let mac = HMAC<SHA256>.authenticationCode(for: msg, using: SymmetricKey(data: Data(secret.utf8)))
            return ("\(n)", mac.map { String(format: "%02x", $0) }.joined())
        }
        n += 1
    }
}

let privacyURL = URL(string: "https://javedh-dev.github.io/ScaleBar/privacy")!

// Short summary, shared by the welcome window and the Settings tooltip.
let telemetryExplainer = """
Sent to fix bugs and decide what to support: macOS version, Mac type, number of screens, which features are on, and, when something fails, a short error name and the model name of your external monitor (for example "DELL U2723QE").

Also: your country, worked out from your IP address by the server. The IP address itself is not stored.

Never sent: your name, settings, serial numbers, key presses.

Even with this off, a daily anonymous count (app version only) is sent so I know how many people use ScaleBar.
"""

extension App {
    // MARK: Anonymous usage count and diagnostics (tallymoth)

    // Endpoint and signed key come from Info.plist (build.sh); a build without them sends nothing.
    func plist(_ k: String) -> String { Bundle.main.object(forInfoDictionaryKey: k) as? String ?? "" }

    // Daily: a version-only "ping" (always), plus an "active" event with details when diagnostics are on.
    // Separate events so the server can add a coarse location to the diagnostics only.
    func sendTelemetry() {
        let last = UserDefaults.standard.object(forKey: "lastTelemetry") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        var events: [[String: Any]] = [["name": "ping", "props": ["version": appVersion]]]
        if pref("telemetry") {
            #if arch(arm64)
            let arch = "arm64"
            #else
            let arch = "x86_64"
            #endif
            let v = ProcessInfo.processInfo.operatingSystemVersion
            events.append(["name": "active", "props": ["version": appVersion, "os": "\(v.majorVersion).\(v.minorVersion)", "arch": arch,
                "displays": NSScreen.screens.count, "virtual": pref("virtualDisplay") && virtualSupported,
                "ddc": pref("ddc") && ddcSupported, "keys": pref("keys")]])
        }
        post(events) { UserDefaults.standard.set(Date(), forKey: "lastTelemetry") }
    }

    // Only a fixed error name and number, at most once a day per kind. Nothing when diagnostics are off.
    // `monitor` is the marketing name macOS reports (e.g. "DELL U2723QE"), never a serial number. Defaults to the connected external monitors.
    func report(_ kind: String, _ code: Int = 0, monitor: String? = nil) {
        let key = "lastFailure." + kind, last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard pref("telemetry"), Date().timeIntervalSince(last) > 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        let external = ids.prefix(Int(n)).filter { CGDisplayVendorNumber($0) != ourVendor && CGDisplayIsBuiltin($0) == 0 }.map(screenName).joined(separator: ", ")
        let name = String((monitor ?? external).prefix(200))
        post([["name": "failure", "props": ["version": appVersion, "kind": kind, "code": code, "monitor": name]]])
    }

    func post(_ events: [[String: Any]], done: (() -> Void)? = nil) {
        let (url, key, secret) = (plist("TallymothURL"), plist("TallymothKey"), plist("TallymothSecret"))
        guard !url.isEmpty, !key.isEmpty, !secret.isEmpty, let endpoint = URL(string: url + "/v1/events"),
              let body = try? JSONSerialization.data(withJSONObject: ["events": events]) else { return }
        func send(bits: Int, retry: Bool) {
            let ts = String(Int(Date().timeIntervalSince1970))
            let s = tmSign(key: key, secret: secret, ts: ts, body: body, bits: bits, start: UInt64.random(in: 0..<(1 << 32)))
            var req = URLRequest(url: endpoint, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.httpBody = body
            for (k, val) in [("Content-Type", "application/json"), ("X-TM-Key", key), ("X-TM-Timestamp", ts), ("X-TM-Nonce", s.nonce), ("X-TM-Signature", s.sig)] {
                req.setValue(val, forHTTPHeaderField: k)
            }
            URLSession.shared.dataTask(with: req) { _, resp, _ in
                let r = resp as? HTTPURLResponse
                if r?.statusCode == 202 { DispatchQueue.main.async { done?() } }
                else if retry, r?.statusCode == 401, let want = r?.value(forHTTPHeaderField: "X-TM-Pow-Bits").flatMap({ Int($0) }), want > bits, want <= 22 {
                    DispatchQueue.global().async { send(bits: want, retry: false) } // server wants harder proof-of-work
                }
            }.resume()
        }
        DispatchQueue.global(qos: .utility).async { send(bits: 16, retry: true) }
    }

    // First launch, two steps: launch at login, then diagnostics. Nothing is sent before step 2 is answered.
    func welcome() {
        UserDefaults.standard.set(true, forKey: "welcomed")
        NSApp.activate(ignoringOtherApps: true)
        func ask(_ title: String, _ info: String, _ check: String, _ button: String, link: Bool = false) -> Bool {
            let a = NSAlert()
            (a.messageText, a.informativeText) = (title, info)
            a.addButton(withTitle: button)
            if link { a.addButton(withTitle: "Privacy Policy") }
            let box = NSButton(checkboxWithTitle: check, target: nil, action: nil)
            box.state = .on
            a.accessoryView = box
            while a.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(privacyURL) }
            return box.state == .on
        }
        if ask("Welcome to ScaleBar", "It lives in your menu bar.", "Launch at login", "Continue") { try? SMAppService.mainApp.register() }
        UserDefaults.standard.set(ask("Help improve ScaleBar?", telemetryExplainer, "Share diagnostics", "Done", link: true), forKey: "telemetry")
        updateSettings()
    }
}
