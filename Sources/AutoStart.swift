import AppKit

// A launch agent keeps this small, event-driven watcher alive across logins.
// It does not inspect windows, keystrokes, or activity records.
final class AutoStart {
    let targetID = "com.openai.codex"
    let notchID = "local.codexnotch.app"
    var opening = false
    var observers: [NSObjectProtocol] = []
    var appURL: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().appendingPathComponent("Codex Notch.app")
    }
    func launchIfNeeded() {
        guard !opening,
              !NSRunningApplication.runningApplications(withBundleIdentifier: targetID).isEmpty,
              NSRunningApplication.runningApplications(withBundleIdentifier: notchID).isEmpty else { return }
        opening = true
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.arguments = ["--background"]
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.opening = false
                if let error { fputs("Codex Notch launch failed: \(error.localizedDescription)\n", stderr) }
            }
        }
    }
    func start() {
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == self.targetID else { return }
                self.launchIfNeeded()
            })
        }
        launchIfNeeded()
    }
}

@main
enum WatcherMain {
    static func main() {
        if CommandLine.arguments.contains("--status") {
            print("Codex running: \(!NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty)")
            print("Notch running: \(!NSRunningApplication.runningApplications(withBundleIdentifier: "local.codexnotch.app").isEmpty)")
            return
        }
        let watcher = AutoStart()
        watcher.start()
        withExtendedLifetime(watcher) { RunLoop.main.run() }
    }
}
