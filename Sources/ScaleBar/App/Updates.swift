import Cocoa

extension App {
    // MARK: Updates (GitHub Releases)

    func autoCheck() {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        if pref("autoUpdate"), Date().timeIntervalSince(last) > 86_400 { checkForUpdates(manual: false) }
    }

    @objc func checkNow() { checkForUpdates(manual: true) }

    @objc func openUpdate() { if let u = update?.url { NSWorkspace.shared.open(u) } }

    // Asks GitHub for the latest release of the repo in Info.plist (ScaleBarRepo, set by build.sh). It only reports
    // the result and can open the release page; it never downloads or installs anything. No personal data is sent.
    func checkForUpdates(manual: Bool) {
        guard let repo = Bundle.main.object(forInfoDictionaryKey: "ScaleBarRepo") as? String,
              repo.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
              let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            updateText = "Update checks aren't set up in this build (no GitHub repository)."
            return updateSettings()
        }
        updateText = "Checking…"
        updateSettings()
        var req = URLRequest(url: api, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:))
            let code = (resp as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                // Only ever open a page on this repo's GitHub releases.
                guard let tag, let page, page.absoluteString.lowercased().hasPrefix("https://github.com/\(repo.lowercased())/releases/") else {
                    self.updateText = code == 404 ? "No releases published yet." : "⚠︎ Couldn't check for updates. Are you offline?"
                    if manual { self.alert(self.updateText) }
                    return self.updateSettings()
                }
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                if newer(tag, than: appVersion) {
                    self.update = (tag, page)
                    self.updateText = "ScaleBar \(tag) is available. It's also in the menu bar menu."
                    if manual {
                        NSApp.activate(ignoringOtherApps: true)
                        let a = NSAlert()
                        a.messageText = "ScaleBar \(tag) is available"
                        a.informativeText = "You have \(appVersion). Open the release page to download it?"
                        a.addButton(withTitle: "Open Release Page"); a.addButton(withTitle: "Later")
                        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
                    }
                } else {
                    self.update = nil
                    self.updateText = "You're up to date (\(appVersion))."
                    if manual { self.alert(self.updateText) }
                }
                self.updateSettings()
            }
        }.resume()
    }
}
