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
