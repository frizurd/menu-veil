// Menu Veil: disposable prototype; Accessibility is used to read menu geometry.
import AppKit
import ApplicationServices
import QuartzCore

struct MenuMeasurement {
    let pid: pid_t
    let frame: CGRect
    let tracking: Bool
    let count: Int
}

// Read the real menu items, including disabled headings and the Apple menu.
// Do not guess widths from app names, or capture/recognize screen pixels.
func measureMenus(pid: pid_t) -> MenuMeasurement? {
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.15)
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    guard let value = attribute(application, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    let menuBar = value as! AXUIElement
    guard let children = attribute(menuBar, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    var bounds = CGRect.null
    var count = 0
    var tracking = !(attribute(menuBar, kAXSelectedChildrenAttribute) as? [AXUIElement] ?? []).isEmpty
    for child in children {
        guard attribute(child, kAXRoleAttribute) as? String == kAXMenuBarItemRole,
              let position = attribute(child, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let sizeValue = attribute(child, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { continue }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0, size.height < 80 else { continue }
        bounds = bounds.union(CGRect(origin: origin, size: size))
        count += 1
        tracking = tracking || (attribute(child, kAXSelectedAttribute) as? Bool == true)
    }
    guard count > 1, !bounds.isNull else { return nil }
    return MenuMeasurement(pid: pid, frame: bounds, tracking: tracking, count: count)
}

final class CoverPanel: NSPanel {
    var targetAlpha: CGFloat = -1
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WallpaperStrip: NSView {
    let screenFrame: NSRect
    let wallpaper: NSImage?
    var mode: Int

    init(frame: NSRect, screen: NSScreen, mode: Int) {
        screenFrame = screen.frame
        wallpaper = NSWorkspace.shared.desktopImageURL(for: screen).flatMap { NSImage(contentsOf: $0) }
        self.mode = mode
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func draw(_ dirtyRect: NSRect) {
        (mode == 2 ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.12, alpha: 1)).setFill()
        bounds.fill()
        guard mode == 0, let wallpaper, wallpaper.size.width > 0, wallpaper.size.height > 0 else { return }
        // Reconstruct the desktop's aspect-fill image; never capture the screen.
        let scale = max(screenFrame.width / wallpaper.size.width, screenFrame.height / wallpaper.size.height)
        let size = NSSize(width: wallpaper.size.width * scale, height: wallpaper.size.height * scale)
        let destination = NSRect(x: (screenFrame.width - size.width) / 2,
                                 y: (screenFrame.height - size.height) / 2 - screenFrame.height + bounds.height,
                                 width: size.width, height: size.height)
        wallpaper.draw(in: destination, from: .zero, operation: .copy, fraction: 1)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var covers: [CoverPanel] = []
    var timer: Timer?
    var enabled = true
    var revealOnHover = true
    var measuredWidth: CGFloat?
    var measurement: MenuMeasurement?
    var frontPID: pid_t = 0
    var readingMenus = false
    var lastMeasurementAt = Date.distantPast
    let measurementQueue = DispatchQueue(label: "local.menu-veil.menu-geometry", qos: .userInitiated)
    var accessibilityGranted = false
    var setupWindow: NSWindow?
    var mode = 0
    var revealUntil = Date.distantPast
    var menuOpen = false
    var isRevealed = false
    var tickCount = 0
    var toggleItem: NSMenuItem!
    var hoverItem: NSMenuItem!
    var sizingItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.lefthalf.inset.filled", accessibilityDescription: "Menu Veil")
        status.button?.toolTip = "Menu Veil — hover top left to reveal menus"
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Menu Veil · Prototype", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        toggleItem = item("Hide left menus", #selector(toggle), menu)
        hoverItem = item("Reveal when hovering top left", #selector(toggleHover), menu)
        item("Reveal for 10 seconds", #selector(reveal), menu)
        sizingItem = NSMenuItem(title: "Automatic sizing · waiting for permission", action: nil, keyEquivalent: "")
        menu.addItem(sizingItem)
        item("Set up automatic sizing…", #selector(showSetup), menu)
        let backgrounds = NSMenu()
        for (index, name) in ["Wallpaper", "Dark solid", "Light solid"].enumerated() {
            let entry = item(name, #selector(changeBackground(_:)), backgrounds)
            entry.tag = index
        }
        let backgroundItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        backgroundItem.submenu = backgrounds
        menu.addItem(backgroundItem)
        menu.addItem(.separator())
        item("Quit Menu Veil", #selector(quit), menu)
        status.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(rebuild), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        rebuild()
        refreshMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        print("Menu Veil running. Public window levels: mainMenu=\(NSWindow.Level.mainMenu.rawValue), status=\(NSWindow.Level.statusBar.rawValue).")
        for screen in NSScreen.screens {
            print("Display: \(screen.localizedName), frame=\(screen.frame), menuHeight=\(screen.safeAreaInsets.top), wallpaperAvailable=\(NSWorkspace.shared.desktopImageURL(for: screen) != nil)")
        }
        fflush(stdout)
        if !AXIsProcessTrusted() { showSetup() }
        if let flag = CommandLine.arguments.firstIndex(of: "--quit-after"), flag + 1 < CommandLine.arguments.count,
           let seconds = Double(CommandLine.arguments[flag + 1]) {
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in NSApp.terminate(nil) }
        }
    }

    @discardableResult
    func item(_ title: String, _ action: Selector, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    @objc func rebuild() {
        covers.forEach { $0.close() }
        covers = NSScreen.screens.map { screen in
            let height = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                              width: min(measuredWidth ?? 1, screen.frame.width), height: height)
            let panel = CoverPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Menu Veil Cover"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.animationBehavior = .none
            panel.alphaValue = 0
            panel.contentView = WallpaperStrip(frame: NSRect(origin: .zero, size: rect.size), screen: screen, mode: mode)
            return panel
        }
        tick()
    }

    func tick() {
        updateMeasurement()
        let pointer = NSEvent.mouseLocation
        let overStrip = measuredWidth != nil && covers.contains { $0.frame.insetBy(dx: 0, dy: -3).contains(pointer) }
        if revealOnHover && overStrip {
            // Leave a grace period to move into a dropdown without hiding its heading.
            revealUntil = Date().addingTimeInterval(0.55)
        }
        let shouldReveal = menuOpen || measurement?.tracking == true || (revealOnHover && overStrip) || Date() < revealUntil
        if shouldReveal != isRevealed {
            isRevealed = shouldReveal
            print("Menus \(shouldReveal ? "revealed" : "covered"); pointer=\(pointer)")
            fflush(stdout)
        }
        for cover in covers {
            let alpha: CGFloat = enabled && measuredWidth != nil && accessibilityGranted && !shouldReveal ? 1 : 0
            guard cover.targetAlpha != alpha else { continue }
            cover.targetAlpha = alpha
            if !cover.isVisible { cover.orderFrontRegardless() }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (alpha == 0 ? 0.20 : 0.32)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                cover.animator().alphaValue = alpha
            }
        }
        tickCount += 1
        if tickCount % 25 == 0 { writeStatus() }
    }

    func updateMeasurement() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
            if !trusted { measuredWidth = nil; measurement = nil }
            else { setupWindow?.close(); setupWindow = nil }
        }
        guard trusted, let front = NSWorkspace.shared.frontmostApplication else {
            sizingItem.title = "Automatic sizing · needs Accessibility"
            return
        }
        // The setup window has no app menus of its own; keep the previous measurement.
        guard front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if front.processIdentifier != frontPID {
            frontPID = front.processIdentifier
            measuredWidth = nil
            measurement = nil
            lastMeasurementAt = .distantPast
            covers.forEach { $0.alphaValue = 0; $0.targetAlpha = -1 }
        }
        guard !readingMenus, Date().timeIntervalSince(lastMeasurementAt) >= 0.4 else { return }
        readingMenus = true
        lastMeasurementAt = Date()
        let pid = frontPID
        measurementQueue.async { [weak self] in
            let result = measureMenus(pid: pid)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.readingMenus = false
                guard self.frontPID == pid, let result else { return }
                self.measurement = result
                // AX coordinates start at the top-left of the primary display.
                let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
                let source = NSScreen.screens.first { screen in
                    CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY,
                           width: screen.frame.width, height: screen.frame.height).contains(result.frame.origin)
                } ?? NSScreen.main
                let width = ceil(result.frame.maxX - (source?.frame.minX ?? result.frame.minX) + 6)
                guard width > 30 else { return }
                self.measuredWidth = width
                self.sizingItem.title = "Automatic sizing · \(Int(width)) pt · \(result.count) menus"
                for cover in self.covers {
                    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cover.frame.origin) }) else { continue }
                    var frame = cover.frame
                    frame.size.width = min(width, screen.frame.width)
                    if cover.frame != frame {
                        cover.setFrame(frame, display: true)
                        cover.contentView?.needsDisplay = true
                    }
                }
                self.tick()
            }
        }
    }

    func writeStatus() {
        let data: [String: Any] = [
            "enabled": enabled, "revealed": isRevealed, "hoverReveal": revealOnHover,
            "width": measuredWidth ?? 0, "background": mode,
            "automaticSizing": true, "accessibilityGranted": accessibilityGranted,
            "menuCount": measurement?.count ?? 0,
            "frontmostApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown",
            "panels": covers.map { ["number": $0.windowNumber, "visible": $0.isVisible, "alpha": $0.alphaValue, "targetAlpha": $0.targetAlpha, "level": $0.level.rawValue, "frame": NSStringFromRect($0.frame)] }
        ]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-veil-prototype-status.json"), options: .atomic)
        }
    }

    func refreshMenu() {
        toggleItem.state = enabled ? .on : .off
        hoverItem.state = revealOnHover ? .on : .off
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; tick() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; tick() }
    @objc func toggle() { enabled.toggle(); refreshMenu(); tick() }
    @objc func toggleHover() { revealOnHover.toggle(); refreshMenu(); tick() }
    @objc func reveal() { revealUntil = Date().addingTimeInterval(10); tick() }
    @objc func changeBackground(_ sender: NSMenuItem) { mode = sender.tag; rebuild() }
    @objc func showSetup() {
        if let setupWindow { setupWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 250),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Menu Veil — Automatic sizing"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Follow each app’s menus automatically")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        title.frame = NSRect(x: 28, y: 190, width: 430, height: 28)
        let body = NSTextField(wrappingLabelWithString: "macOS requires Accessibility permission to read menu item positions. Menu Veil uses those bounds to fit the cover automatically as you switch apps. It does not capture your screen.\n\nEnable Menu Veil in Privacy & Security → Accessibility. Until then, the menus stay visible.")
        body.frame = NSRect(x: 28, y: 64, width: 424, height: 118)
        let button = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibility))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 220, y: 20, width: 235, height: 32)
        window.contentView?.addSubview(title)
        window.contentView?.addSubview(body)
        window.contentView?.addSubview(button)
        window.center()
        setupWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    @objc func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        covers.forEach { $0.orderOut(nil) }
        print("Menu Veil stopped; menus restored.")
        fflush(stdout)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
