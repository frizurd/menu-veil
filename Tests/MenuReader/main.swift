import AppKit
import ApplicationServices

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { print("FAIL \(name)"); exit(1) }
    print("PASS \(name)")
}
let application = AXUIElementCreateApplication(-1)
let bar = AXUIElementCreateApplication(-2)
let headings = (3...5).map { AXUIElementCreateApplication(-Int32($0)) }
func snapshot(missing: String? = nil, changing: Bool = false, invalid: Bool = false) -> MenuMeasurement? {
    var childrenReads = 0
    return readMenuSnapshot(pid: -1, application: application) { element, name in
        if CFEqual(element, application), name == kAXMenuBarAttribute { return bar }
        if CFEqual(element, bar), name == kAXChildrenAttribute {
            childrenReads += 1
            return (changing && childrenReads > 1 ? Array(headings.reversed()) : headings) as CFArray
        }
        guard let index = headings.firstIndex(where: { CFEqual($0, element) }) else { return nil }
        // The trailing heading is still part of the menu when its bounds fail.
        if index == 2, name == missing { return nil }
        switch name {
        case kAXRoleAttribute: return kAXMenuBarItemRole as CFString
        case kAXPositionAttribute:
            var point = CGPoint(x: invalid && index == 2 ? .nan : CGFloat(index * 100), y: 0)
            return AXValueCreate(.cgPoint, &point)
        case kAXSizeAttribute:
            var size = CGSize(width: 100, height: 32)
            return AXValueCreate(.cgSize, &size)
        default: return nil
        }
    }
}
check(snapshot()?.frame.maxX == 300, "complete snapshot includes the last menu heading")
check(snapshot(missing: kAXPositionAttribute) == nil, "missing trailing position cannot produce a truncated cover")
check(snapshot(missing: kAXSizeAttribute) == nil, "missing trailing size cannot produce a truncated cover")
check(snapshot(missing: kAXRoleAttribute) == nil, "unreadable trailing heading cannot produce a truncated cover")
check(snapshot(changing: true) == nil, "children replaced during activation cannot produce mixed bounds")
check(snapshot(invalid: true) == nil, "nonfinite menu bounds cannot reach a window")
