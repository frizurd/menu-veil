import Foundation
import CoreGraphics

// Own the safety rule in one place, independent of timers and AppKit callbacks.
struct RuntimePolicy {
    static let geometryLifetime: TimeInterval = 5
    static let appSwitchGrace: TimeInterval = 0.5
    static func mayCover(installed: Bool, trusted: Bool, enabled: Bool, awake: Bool,
                         measuredAt: Date?, now: Date, switchingUntil: Date? = nil) -> Bool {
        guard installed, trusted, enabled, awake, let measuredAt else { return false }
        if let switchingUntil, now >= switchingUntil { return false }
        return now.timeIntervalSince(measuredAt) >= 0 && now.timeIntervalSince(measuredAt) <= geometryLifetime
    }
    static func measurementInterval(revealed: Bool) -> TimeInterval { revealed ? 0.5 : 3 }
    static func acceptsResult(generation: Int, requestedGeneration: Int, pid: Int32, requestedPID: Int32,
                              trusted: Bool, awake: Bool, startedAt: Date, now: Date) -> Bool {
        generation == requestedGeneration && pid == requestedPID && trusted && awake &&
        now.timeIntervalSince(startedAt) >= 0 && now.timeIntervalSince(startedAt) < 1
    }
    static func belongsToDisplay(menu: CGRect, display: CGRect) -> Bool {
        menu.width > 30 && menu.height > 0 && menu.height < 80 &&
        display.contains(CGPoint(x: menu.minX, y: menu.minY)) && abs(menu.minY - display.minY) < 4
    }
}
