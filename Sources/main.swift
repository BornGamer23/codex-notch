import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NotchPanel!
    var hud = HUDView(frame: NSRect(x: 0, y: 0, width: 480, height: 164))
    var preview: HUDView?
    var statusItem: NSStatusItem!
    var controlWindow: NSWindow?
    var connectionLabel: NSTextField?
    var liveButton: NSButton?
    var demoButton: NSButton?
    var monitor: ActivityMonitor?
    var heartbeat: Timer?
    var demoTimer: Timer?
    var demoIndex = 0
    var following = true
    var hovering = false
    var lastActivity = Activity(phase: .idle, detail: "Ready when you are")
    var connection = "Connecting to local Codex activity"
    let defaults = UserDefaults.standard
    var hideIdle: Bool { defaults.bool(forKey: "hideIdle") }
    var alwaysExpanded: Bool { defaults.bool(forKey: "expanded") }
    var root: URL {
        if let path = defaults.string(forKey: "sessionsRoot") { return URL(fileURLWithPath: path) }
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("sessions")
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["glow": 0.75, "expanded": false, "hideIdle": false, "reduceMotion": false])
        NSApp.setActivationPolicy(.accessory)
        setupPanel(); setupMenu(); startMonitor()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(self, selector: #selector(reposition), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !CommandLine.arguments.contains("--background") { showControls() }
        if CommandLine.arguments.contains("--demo") { toggleDemo() }
    }
    func setupPanel() {
        panel = NotchPanel(contentRect: hud.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Codex Notch HUD"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.contentView = hud
        hud.onClick = { [weak self] in self?.showControls() }
        hud.onHover = { [weak self] value in self?.hovering = value; self?.refresh() }
        reposition(); panel.orderFrontRegardless()
    }
    @objc func reposition() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else { return }
        hud.topInset = max(8, screen.safeAreaInsets.top)
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hud.minimumWidth = max(210, screen.frame.width - left.width - right.width + 12)
        } else { hud.minimumWidth = 210 }
        let width = max(310, hud.minimumWidth) + 56
        let height = hud.topInset + 81
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }
    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Codex Notch")
        statusItem.button?.toolTip = "Codex Notch — local activity HUD"
        let menu = NSMenu()
        let actions: [(String, Selector?, String)] = [
            ("Codex Notch…", #selector(showControls), ","),
            ("Play / stop demo", #selector(toggleDemo), "d"),
            ("Pause / resume activity", #selector(toggleLive), "p"),
            ("", nil, ""),
            ("Choose sessions folder…", #selector(chooseFolder), ""),
            ("", nil, ""),
            ("Quit Codex Notch", #selector(quit), "q")
        ]
        for (title, action, key) in actions {
            if action == nil { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        statusItem.menu = menu
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let quitItem = NSMenuItem(title: "Quit Codex Notch", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self
        appMenu.addItem(quitItem); NSApp.mainMenu = main
    }
    func startMonitor() {
        monitor?.stop()
        monitor = ActivityMonitor(root: root)
        monitor?.onActivity = { [weak self] activity in
            guard let self else { return }
            self.lastActivity = activity
            if self.following && self.demoTimer == nil { self.hud.activity = activity; self.refresh() }
        }
        monitor?.onConnection = { [weak self] text in self?.connection = text; self?.refresh() }
        monitor?.start()
    }
    func refresh() {
        if demoTimer == nil {
            if !following { hud.activity = Activity(phase: .waiting, detail: "Activity monitoring paused") }
            else {
                let age = Date().timeIntervalSince(lastActivity.date)
                if lastActivity.phase == .complete && age > 8 { hud.activity = Activity(phase: .idle, detail: "Ready for your next idea") }
                else if lastActivity.phase.active && age > 180 { hud.activity = Activity(phase: .waiting, detail: "No recent activity • check Codex") }
                else { hud.activity = lastActivity }
            }
        }
        hud.expanded = alwaysExpanded || hovering || hud.activity.phase.active || hud.activity.phase == .complete || demoTimer != nil
        hud.reduceMotion = defaults.bool(forKey: "reduceMotion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        hud.glow = defaults.double(forKey: "glow")
        hud.demo = demoTimer != nil
        let hidden = hideIdle && hud.activity.phase == .idle && demoTimer == nil
        if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        preview?.activity = hud.activity; preview?.demo = hud.demo; preview?.glow = hud.glow; preview?.reduceMotion = hud.reduceMotion
        connectionLabel?.stringValue = demoTimer != nil ? "Demo playing · real activity resumes when you stop" : (!following ? "Paused · resume to follow Codex" : connection)
        liveButton?.title = following ? "Pause activity" : "Resume activity"
        demoButton?.title = demoTimer == nil ? "Play demo" : "Stop demo"
    }
    @objc func toggleLive() { following.toggle(); refresh() }
    @objc func toggleDemo() {
        if demoTimer != nil { demoTimer?.invalidate(); demoTimer = nil; refresh(); return }
        demoIndex = 0; demoStep()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { [weak self] _ in self?.demoStep() }
        refresh()
    }
    func demoStep() {
        let frames: [(Phase, String)] = [(.reading, "Read app-sidebar.tsx"), (.thinking, "Connecting the dots"), (.reading, "Read theme.css"), (.building, "Shaping your prototype"), (.building, "Checking the finishing touches"), (.answering, "Putting it into words"), (.complete, "Your response is ready in Codex")]
        let frame = frames[demoIndex % frames.count]; demoIndex += 1
        hud.activity = Activity(phase: frame.0, detail: frame.1)
        preview?.activity = hud.activity
    }
    @objc func showControls() {
        if let window = controlWindow { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Codex Notch"; window.backgroundColor = cream; window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 590)); window.contentView = view
        func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ size: CGFloat, _ color: NSColor = .labelColor, _ weight: NSFont.Weight = .regular) -> NSTextField {
            let l = NSTextField(labelWithString: text); l.frame = NSRect(x: x, y: y, width: width, height: size + 10); l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; view.addSubview(l); return l
        }
        _ = label("CODEX NOTCH", 36, 539, 400, 11, .secondaryLabelColor, .semibold)
        _ = label("A little presence. A lot in motion.", 36, 495, 560, 26, .black, .medium)
        _ = label("Your agent’s rhythm, at the edge of your screen.", 36, 463, 550, 15, .secondaryLabelColor)
        let tile = NSView(frame: NSRect(x: 36, y: 266, width: 548, height: 178)); tile.wantsLayer = true; tile.layer?.backgroundColor = NSColor(calibratedWhite: 0.90, alpha: 1).cgColor; tile.layer?.cornerRadius = 14
        view.addSubview(tile)
        let pv = HUDView(frame: NSRect(x: 0, y: 0, width: 548, height: 177)); pv.topInset = 15; pv.preview = true; pv.expanded = true; pv.activity = hud.activity; tile.addSubview(pv); preview = pv
        _ = label("LIVE PREVIEW", 52, 276, 160, 10, .secondaryLabelColor, .medium)
        func button(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action); b.frame = NSRect(x: x, y: y, width: width, height: 34); b.bezelStyle = .rounded; view.addSubview(b); return b
        }
        demoButton = button("Play demo", x: 36, y: 215, width: 120, action: #selector(toggleDemo))
        liveButton = button("Pause activity", x: 166, y: 215, width: 140, action: #selector(toggleLive))
        _ = button("Sessions folder…", x: 431, y: 215, width: 153, action: #selector(chooseFolder))
        let options: [(String, String, CGFloat)] = [("Keep expanded", "expanded", 36), ("Hide when idle", "hideIdle", 220), ("Reduce motion", "reduceMotion", 416)]
        for (title, key, x) in options {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(changeOption(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(key); b.state = defaults.bool(forKey: key) ? .on : .off
            b.frame = NSRect(x: x, y: 166, width: 170, height: 25); view.addSubview(b)
        }
        _ = label("Glow", 38, 120, 60, 14)
        let slider = NSSlider(value: defaults.double(forKey: "glow"), minValue: 0, maxValue: 1, target: self, action: #selector(changeGlow(_:)))
        slider.frame = NSRect(x: 103, y: 123, width: 280, height: 20); slider.setAccessibilityLabel("Glow intensity"); view.addSubview(slider)
        _ = label("Soft", 399, 120, 160, 13, .secondaryLabelColor)
        connectionLabel = label(connection, 36, 65, 550, 13, .secondaryLabelColor)
        _ = label("On-device only · follows the most recently active local task", 36, 33, 550, 12, .tertiaryLabelColor)
        controlWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); refresh()
    }
    @objc func changeOption(_ sender: NSButton) { defaults.set(sender.state == .on, forKey: sender.identifier!.rawValue); refresh() }
    @objc func changeGlow(_ sender: NSSlider) { defaults.set(sender.doubleValue, forKey: "glow"); refresh() }
    @objc func chooseFolder() {
        let picker = NSOpenPanel(); picker.title = "Choose Codex sessions"; picker.message = "Select the sessions folder inside your Codex home folder."; picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = false; picker.showsHiddenFiles = true; picker.directoryURL = root
        if picker.runModal() == .OK, let url = picker.url { defaults.set(url.path, forKey: "sessionsRoot"); lastActivity = Activity(phase: .idle, detail: "Ready when you are"); startMonitor(); refresh() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { monitor?.stop(); heartbeat?.invalidate(); demoTimer?.invalidate() }
}

if CommandLine.arguments.contains("--self-test") {
    runTests()
} else if CommandLine.arguments.contains("--probe") {
    let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    let monitor = ActivityMonitor(root: home.appendingPathComponent("sessions"))
    var observed = false
    monitor.onActivity = { activity in observed = true; print("Observed live activity: \(activity.phase.rawValue)") }
    monitor.onConnection = { print($0) }
    monitor.start()
    RunLoop.current.run(until: Date().addingTimeInterval(4))
    monitor.stop()
    if !observed { print("No activity in the last two minutes.") }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
