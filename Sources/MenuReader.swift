import AppKit
import ApplicationServices

struct MenuMeasurement {
    let pid: pid_t
    let frame: CGRect
    let tracking: Bool
    let count: Int
}

// Read the real menu items, including disabled headings and the Apple menu.
// Do not guess widths from app names, or capture/recognize screen pixels.
func measureMenus(pid: pid_t) -> MenuMeasurement? {
    let deadline = ProcessInfo.processInfo.systemUptime + 0.35
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.1)
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    let result = readMenuSnapshot(pid: pid, application: application, attribute: attribute)
    return ProcessInfo.processInfo.systemUptime < deadline ? result : nil
}

// Keep snapshot validation independent of AX transport so incomplete activation
// layouts can be replayed without permission or changing the foreground app.
func readMenuSnapshot(pid: pid_t, application: AXUIElement,
                      attribute: (AXUIElement, String) -> CFTypeRef?) -> MenuMeasurement? {
    guard let value = attribute(application, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    let menuBar = value as! AXUIElement
    guard let children = attribute(menuBar, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    var bounds = CGRect.null
    var count = 0
    var tracking = !(attribute(menuBar, kAXSelectedChildrenAttribute) as? [AXUIElement] ?? []).isEmpty
    for child in children {
        guard let role = attribute(child, kAXRoleAttribute) as? String else { return nil }
        guard role == kAXMenuBarItemRole else { continue }
        // A missing heading is an incomplete snapshot, not a shorter menu bar.
        guard let position = attribute(child, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let sizeValue = attribute(child, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, size.height < 80 else { return nil }
        bounds = bounds.union(CGRect(origin: origin, size: size))
        count += 1
        tracking = tracking || (attribute(child, kAXSelectedAttribute) as? Bool == true)
    }
    // Activation can replace the children while their frames are being read.
    guard count > 1, !bounds.isNull,
          let currentChildren = attribute(menuBar, kAXChildrenAttribute) as? [AXUIElement],
          children.count == currentChildren.count,
          zip(children, currentChildren).allSatisfy({ CFEqual($0.0, $0.1) }) else { return nil }
    return MenuMeasurement(pid: pid, frame: bounds, tracking: tracking, count: count)
}
