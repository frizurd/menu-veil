import AppKit
import ApplicationServices
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "local.menu-veil.geometry", qos: .utility)
    private let observerQueue = DispatchQueue(label: "local.menu-veil.observer", qos: .utility)
    private var status: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var hoverItem: NSMenuItem!
    private var sizingItem: NSMenuItem!
    private var covers: [CoverPanel] = []
    private var heartbeat: Timer?
    private var concealTask: DispatchWorkItem?
    private var queryTask: DispatchWorkItem?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var reader: AXObserver?
    private var observerGeneration = 0
    private var reading = false
    private var generation = 0
    private var pid: pid_t = 0
    private var measuredAt: Date?
    private var switchingUntil: Date?
    private var switchExpiryTask: DispatchWorkItem?
    private var lastAttempt = Date.distantPast
    private var measurement: MenuMeasurement?
    private var coverWidths: [CGDirectDisplayID: CGFloat] = [:]
    private var widthCache: [String: CGFloat] = [:]
    private var settlingUntil = Date.distantPast
    private var trusted = false
    private var awake = true
    private var hovering = false
    private var menuOpen = false
    private var revealUntil = Date.distantPast
    private var setupWindow: NSWindow?
    private var setupStatus: NSTextField?
    private var setupButton: NSButton?
    private var lastDisplay: CGDirectDisplayID?
    private var diagnosticState = ""
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var hoverEnabled = UserDefaults.standard.object(forKey: "hover") as? Bool ?? true
    private var mode = UserDefaults.standard.integer(forKey: "background")
    private var diagnosticMode: Bool { CommandLine.arguments.contains("--diagnostics") }
    private lazy var installed: Bool = {
        if CommandLine.arguments.contains("--allow-development") { return true }
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }()
    private var permissionName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }
    private var revealed: Bool { hovering || menuOpen || measurement?.tracking == true || Date() < revealUntil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // A duplicate launch must never create another cover or another permission request.
        let identity = Bundle.main.bundleIdentifier ?? "local.frizurd.menu-veil-prototype"
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == identity && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(identity + ".showSetup"), object: nil)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showSetup), name: Notification.Name(identity + ".showSetup"), object: nil)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.lefthalf.inset.filled", accessibilityDescription: "Menu Veil")
        status.button?.toolTip = "Menu Veil — hover over the left menus to reveal them"
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Menu Veil", action: nil, keyEquivalent: "")
        menu.addItem(title)
        sizingItem = NSMenuItem(title: "Checking permission…", action: nil, keyEquivalent: "")
        menu.addItem(sizingItem)
        menu.addItem(.separator())
        toggleItem = item("Hide left menus", #selector(toggle), menu)
        hoverItem = item("Reveal on hover", #selector(toggleHover), menu)
        item("Show menus for 10 seconds", #selector(reveal), menu)
        let backgrounds = NSMenu()
        for (index, name) in ["Wallpaper", "Dark", "Light"].enumerated() {
            let entry = item(name, #selector(changeBackground(_:)), backgrounds)
            entry.tag = index
        }
        let background = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        background.submenu = backgrounds
        menu.addItem(background)
        menu.addItem(.separator())
        item("Setup & troubleshooting…", #selector(showSetup), menu)
        item("Quit Menu Veil", #selector(quit), menu).keyEquivalent = "q"
        status.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.frontChanged() }
        observe(center, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.invalidateGeometry(); self?.scheduleQuery() }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(center, name) { [weak self] in self?.awake = false; self?.invalidateGeometry(); self?.refreshVisibility() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(center, name) { [weak self] in self?.awake = true; self?.frontChanged() }
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.coverWidths.removeAll(); self?.widthCache.removeAll(); self?.invalidateGeometry(); self?.scheduleQuery() }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { [weak self] in self?.healthCheck() }
        heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.healthCheck() }
        heartbeat?.tolerance = 0.25
        RunLoop.main.add(heartbeat!, forMode: .common)
        healthCheck()
        if !installed || !trusted || !defaults.bool(forKey: "onboarded") || CommandLine.arguments.contains("--onboarding") { showSetup() }
        if let index = CommandLine.arguments.firstIndex(of: "--quit-after"), index + 1 < CommandLine.arguments.count,
           let seconds = Double(CommandLine.arguments[index + 1]), seconds > 0 {
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in NSApp.terminate(nil) }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in action() })
    }
    @discardableResult private func item(_ title: String, _ action: Selector, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; menu.addItem(entry); return entry
    }
    private func invalidateGeometry() {
        generation += 1
        switchExpiryTask?.cancel(); switchExpiryTask = nil; switchingUntil = nil
        queryTask?.cancel(); queryTask = nil; settlingUntil = .distantPast
        measuredAt = nil; measurement = nil; lastAttempt = .distantPast
        covers.forEach { $0.orderOut(nil); $0.close() }; covers.removeAll()
    }
    private func frontChanged() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if pid != app.processIdentifier { beginHandoff(to: app.processIdentifier) }
        else { scheduleQuery() }
    }
    private func beginHandoff(to nextPID: pid_t) {
        pid = nextPID
        menuOpen = false
        revealUntil = .distantPast
        // An app switch is a handoff, not a loss of permission/geometry.
        // Keep the existing window and opacity while its bounds are refreshed.
        generation += 1
        measurement = nil
        lastAttempt = .distantPast
        settlingUntil = Date().addingTimeInterval(RuntimePolicy.appSwitchSettling)
        if let panel = covers.first, let screen = panel.screen,
           let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            var frame = panel.frame
            frame.size.width = RuntimePolicy.coverWidth(measured: frame.width,
                retained: coverWidths[display] ?? 0, displayWidth: screen.frame.width)
            panel.setFrame(frame, display: true)
            panel.contentView?.needsDisplay = true
        }
        switchExpiryTask?.cancel()
        let deadline = Date().addingTimeInterval(RuntimePolicy.appSwitchGrace)
        switchingUntil = deadline
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.switchingUntil == deadline else { return }
            self.invalidateGeometry(); self.refreshVisibility()
        }
        switchExpiryTask = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + RuntimePolicy.appSwitchGrace, execute: expiry)
        queryTask?.cancel(); queryTask = nil
        queryMenus()
        refreshVisibility(animate: false)
        attachObserver()
    }
    private func attachObserver() {
        observerGeneration += 1
        if let reader { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(reader), .commonModes) }
        reader = nil
        guard trusted, awake, pid > 0 else { return }
        let requestedPID = pid, token = observerGeneration
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Notification registration is synchronous IPC. A slow app must not
        // block the main thread, the cover, or the new app's geometry query.
        observerQueue.async { [weak self] in
            var value: AXObserver?
            guard AXObserverCreate(requestedPID, { _, element, notification, context in
                guard let context else { return }
                let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                var notificationPID: pid_t = 0
                guard AXUIElementGetPid(element, &notificationPID) == .success, notificationPID == owner.pid else { return }
                if notification as String == kAXMenuOpenedNotification || notification as String == kAXMenuClosedNotification {
                    owner.revealUntil = Date().addingTimeInterval(0.55)
                    owner.refreshVisibility()
                }
                owner.scheduleQuery()
            }, &value) == .success, let value else { return }
            let app = AXUIElementCreateApplication(requestedPID)
            AXUIElementSetMessagingTimeout(app, 0.1)
            for name in [kAXFocusedWindowChangedNotification, kAXMenuOpenedNotification, kAXMenuClosedNotification, kAXLayoutChangedNotification] {
                AXObserverAddNotification(value, app, name as CFString, context)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observerGeneration == token, self.pid == requestedPID, self.trusted, self.awake else { return }
                self.reader = value
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(value), .commonModes)
            }
        }
    }
    private func scheduleQuery() {
        // Coalesce notifications without moving an already scheduled read back.
        // Continuous layout events must not starve the handoff measurement.
        guard queryTask == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.queryTask = nil; self?.queryMenus() }
        queryTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    private func healthCheck() {
        guard status != nil else { return }
        // Do no Accessibility work while asleep or while the user session is inactive.
        guard awake else { refreshVisibility(); return }
        let access = installed && AXIsProcessTrusted()
        if access != trusted {
            trusted = access
            invalidateGeometry()
            attachObserver()
        }
        frontChangedIfNeeded()
        if installed && trusted && enabled && Date().timeIntervalSince(lastAttempt) >= RuntimePolicy.measurementInterval(revealed: revealed) { queryMenus() }
        refreshVisibility()
        refreshSetup()
    }
    private func frontChangedIfNeeded() {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if front.processIdentifier != pid { frontChanged() }
    }
    private func queryMenus() {
        guard installed, trusted, enabled, awake, !reading, pid > 0 else { return }
        reading = true
        lastAttempt = Date()
        let requestedPID = pid, token = generation
        let startedAt = Date()
        queue.async { [weak self] in
            let result = measureMenus(pid: requestedPID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reading = false
                self.frontChangedIfNeeded()
                self.receiveMeasurement(result, requestedPID: requestedPID, token: token, startedAt: startedAt)
            }
        }
    }
    private func receiveMeasurement(_ result: MenuMeasurement?, requestedPID: pid_t, token: Int, startedAt: Date) {
        // A response from the previous app must not tear down the cover
        // retained for the new app, or restart its measurement generation.
        guard generation == token, pid == requestedPID else { queryMenus(); return }
        guard RuntimePolicy.acceptsResult(generation: generation, requestedGeneration: token,
            pid: pid, requestedPID: requestedPID, trusted: trusted, awake: awake,
            startedAt: startedAt, now: Date()) else { invalidateGeometry(); scheduleQuery(); return }
        guard let result else {
            if Date() < settlingUntil { scheduleQuery(); return }
            // Never leave an old cover over menus we can no longer locate.
            invalidateGeometry(); refreshVisibility(); return
        }
        measurement = result
        measuredAt = Date()
        switchExpiryTask?.cancel(); switchExpiryTask = nil; switchingUntil = nil
        applyGeometry(result)
        pointerChanged(animate: false)
        refreshSetup()
        // The first successful AX read may precede the final menu layout.
        // Keep sampling through the activation burst, without resizing down.
        if Date() < settlingUntil { scheduleQuery() }
    }
    private func applyGeometry(_ result: MenuMeasurement) {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard let screen = NSScreen.screens.first(where: {
            RuntimePolicy.belongsToDisplay(menu: result.frame, display: CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height))
        }) else { invalidateGeometry(); return }
        let height = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        guard let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { invalidateGeometry(); return }
        let measuredWidth = min(ceil(result.frame.maxX - screen.frame.minX + 6), screen.frame.width)
        let settling = Date() < settlingUntil
        let key = "\(result.pid):\(display)"
        let appWidth = settling ? max(measuredWidth, widthCache[key] ?? 0) : measuredWidth
        let width = RuntimePolicy.coverWidth(measured: appWidth,
            retained: settling ? coverWidths[display] ?? 0 : 0, displayWidth: screen.frame.width)
        let frame = CGRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: width, height: height)
        // The wider guard is temporary: settled short menus must give status
        // icons their space back. Cache only measurements, never the guard width.
        if widthCache.count >= 32 { widthCache.removeAll() }
        widthCache[key] = appWidth
        coverWidths[display] = max(coverWidths[display] ?? 0, measuredWidth)
        // Only cover the display whose menu bounds were actually measured. Never reuse a guessed width elsewhere.
        if let panel = covers.first, panel.screen == screen {
            if panel.frame != frame { panel.setFrame(frame, display: true); panel.contentView?.needsDisplay = true }
        } else {
            covers.forEach { $0.close() }; covers.removeAll()
            let panel = CoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Menu Veil Cover"; panel.isReleasedWhenClosed = false
            panel.isOpaque = true; panel.backgroundColor = .black; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.animationBehavior = .none; panel.alphaValue = 0
            panel.contentView = WallpaperStrip(frame: CGRect(origin: .zero, size: frame.size), screen: screen, mode: mode)
            covers = [panel]
        }
    }
    private func pointerChanged(animate: Bool = true) {
        guard installed, trusted, awake, enabled else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
        let display = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        if display != lastDisplay { lastDisplay = display; scheduleQuery() }
        hovering = hoverEnabled && covers.contains { $0.frame.insetBy(dx: 0, dy: -3).contains(pointer) }
        if hovering {
            concealTask?.cancel(); concealTask = nil
            revealUntil = Date().addingTimeInterval(0.55)
        } else if Date() < revealUntil && concealTask == nil {
            let work = DispatchWorkItem { [weak self] in self?.concealTask = nil; self?.refreshVisibility() }
            concealTask = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, revealUntil.timeIntervalSinceNow), execute: work)
        }
        refreshVisibility(animate: animate)
    }
    private func syncMouseMonitors() {
        let needed = installed && trusted && awake && enabled
        if !needed {
            monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll(); hovering = false
            return
        }
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.pointerChanged() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.pointerChanged(); return event }) { monitors.append(monitor) }
    }
    private func refreshVisibility(animate: Bool = true) {
        syncMouseMonitors()
        let ready = RuntimePolicy.mayCover(installed: installed, trusted: trusted, enabled: enabled, awake: awake, measuredAt: measuredAt, now: Date(), switchingUntil: switchingUntil)
        let alpha: CGFloat = ready && !revealed ? 1 : 0
        for panel in covers where panel.targetAlpha != alpha || (!animate && alpha == 1) {
            panel.targetAlpha = alpha
            if alpha > 0 && !panel.isVisible { panel.orderFrontRegardless() }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = (!animate && alpha == 1) || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (alpha == 0 ? 0.2 : 0.32)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = alpha
            }
        }
        toggleItem?.state = enabled ? .on : .off
        hoverItem?.state = hoverEnabled ? .on : .off
        sizingItem?.title = !installed ? "Move to Applications first" : !trusted ? "Permission needed — open Setup" : !enabled ? "Paused" : measurement == nil ? "Waiting for the active app’s menus…" : "Automatic sizing · \(measurement!.count) menus"
        if diagnosticMode { writeDiagnostics() }
    }
    private func writeDiagnostics() {
        let state: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "installed": installed, "accessibilityGranted": trusted,
            "setupVisible": setupWindow?.isVisible ?? false, "mouseMonitors": monitors.count, "enabled": enabled, "awake": awake, "revealed": revealed, "menuCount": measurement?.count ?? 0,
            "width": covers.first?.frame.width ?? 0,
            "panels": covers.map { ["frame": NSStringFromRect($0.frame), "targetAlpha": $0.targetAlpha, "alpha": $0.alphaValue] }]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8), string != diagnosticState else { return }
        diagnosticState = string
        try? data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-veil-status.json"), options: .atomic)
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; refreshVisibility() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; pointerChanged() }
    @objc private func toggle() { enabled.toggle(); defaults.set(enabled, forKey: "enabled"); if enabled { scheduleQuery() } else { invalidateGeometry() }; refreshVisibility() }
    @objc private func toggleHover() { hoverEnabled.toggle(); defaults.set(hoverEnabled, forKey: "hover"); hovering = false; pointerChanged() }
    @objc private func reveal() { concealTask?.cancel(); concealTask = nil; revealUntil = Date().addingTimeInterval(10); pointerChanged() }
    @objc private func changeBackground(_ item: NSMenuItem) { mode = item.tag; defaults.set(mode, forKey: "background"); invalidateGeometry(); scheduleQuery() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSetup(); return true }
    @objc private func showSetup() {
        if let setupWindow { setupWindow.makeKeyAndOrderFront(nil); NSApp.activate(); refreshSetup(); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Menu Veil — Setup"
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        let icon = NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
        icon.frame = NSRect(x: 30, y: 530, width: 72, height: 72); content.addSubview(icon)
        let title = NSTextField(labelWithString: "A quieter menu bar.")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        title.frame = NSRect(x: 118, y: 548, width: 445, height: 40); content.addSubview(title)
        func text(_ value: String, y: CGFloat, height: CGFloat, bold: Bool = false) {
            let field = NSTextField(wrappingLabelWithString: value)
            field.font = .systemFont(ofSize: bold ? 16 : 14, weight: bold ? .semibold : .regular)
            field.frame = NSRect(x: 34, y: y, width: 532, height: height)
            content.addSubview(field)
        }
        text("1   Keep one copy in Applications", y: 480, height: 24, bold: true)
        text("Install with Homebrew, or move Menu Veil into Applications before enabling permission. Open that same copy each time.", y: 428, height: 45)
        text("2   Allow menu detection", y: 382, height: 24, bold: true)
        text("Open Privacy & Security → \(permissionName) and enable Menu Veil. It reads menu positions; it doesn’t record your screen or send input to other apps.", y: 312, height: 60)
        text("3   Hover to bring the menus back", y: 268, height: 24, bold: true)
        text("Move over the top-left menu area to reveal it. Move away to hide it. The rectangle icon on the right has pause, background, and quit controls.", y: 200, height: 60)
        let statusLabel = NSTextField(wrappingLabelWithString: "Checking setup…")
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.frame = NSRect(x: 34, y: 132, width: 532, height: 56)
        setupStatus = statusLabel; content.addSubview(statusLabel)
        let permission = NSButton(title: "Open Permission Settings", target: self, action: #selector(openAccessibility))
        permission.bezelStyle = .rounded; permission.frame = NSRect(x: 28, y: 80, width: 252, height: 34); content.addSubview(permission)
        let done = NSButton(title: "Start using Menu Veil", target: self, action: #selector(finishSetup))
        done.bezelStyle = .rounded; done.frame = NSRect(x: 300, y: 80, width: 270, height: 34); setupButton = done; content.addSubview(done)
        let help = NSButton(title: "Permission is on but it still won’t work…", target: self, action: #selector(permissionHelp))
        help.bezelStyle = .inline; help.frame = NSRect(x: 34, y: 34, width: 532, height: 28); content.addSubview(help)
        setupWindow = window; refreshSetup(); window.center(); NSApp.activate(); window.makeKeyAndOrderFront(nil)
    }
    private func refreshSetup() {
        guard setupWindow != nil else { return }
        setupButton?.isEnabled = installed && trusted
        setupStatus?.stringValue = !installed ? "Move this app to /Applications or ~/Applications, then open it there. Permission requests are disabled here."
            : !trusted ? "Waiting for permission. macOS may ask for Touch ID. If the toggle is already on, use the recovery steps below."
            : !enabled ? "Permission is ready. Menu Veil is paused — enable Hide left menus from the rectangle icon."
            : measurement == nil ? "Permission is ready. Switch to another app to detect its menus."
            : "Ready — detected \(measurement!.count) menus. Try hovering over the top-left area."
    }
    @objc private func finishSetup() { defaults.set(true, forKey: "onboarded"); setupWindow?.close(); setupWindow = nil; setupStatus = nil; setupButton = nil }
    @objc private func openAccessibility() {
        guard installed else { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Applications")); return }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func permissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Refresh the grant for this copy"
        alert.informativeText = "In Privacy & Security → \(permissionName), remove old Menu Veil entries with the − button. Then use + to add this copy:\n\n\(Bundle.main.bundlePath)\n\nEnable it, quit Menu Veil, and open it again. macOS can retain an old grant after a development build or a signing change. Your menus stay visible while permission is unavailable."
        alert.addButton(withTitle: "Show This App in Finder")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        heartbeat?.invalidate(); concealTask?.cancel(); queryTask?.cancel(); switchExpiryTask?.cancel()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        if let reader { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(reader), .commonModes) }
        covers.forEach { $0.orderOut(nil) }
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
