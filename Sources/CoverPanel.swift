import AppKit

final class CoverPanel: NSPanel {
    var targetAlpha: CGFloat = -1
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WallpaperStrip: NSView {
    private static let images: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private static func image(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
    let screenFrame: NSRect
    let wallpaper: NSImage?
    var mode: Int

    init(frame: NSRect, screen: NSScreen, mode: Int) {
        screenFrame = screen.frame
        wallpaper = Self.image(for: screen)
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
