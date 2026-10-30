import AppKit
import ApplicationServices

/// Thin, typed wrappers over the Accessibility C API. Safe to call from any thread.
enum AX {
    /// How long one call may wait on an unresponsive app.
    static let timeout: Float = 0.25

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ attribute: String, of element: AXUIElement) -> String? {
        value(attribute, of: element) as? String
    }

    static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = value(attribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ attribute: String, of element: AXUIElement) -> [AXUIElement] {
        guard let value = value(attribute, of: element), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as! [AnyObject]).compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = value(kAXPositionAttribute, of: window), let sizeValue = value(kAXSizeAttribute, of: window),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// Best effort: a fixed-size window still moves even if it won't resize.
    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Shrinking first avoids the window being pushed when it doesn't fit at the new origin.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    /// pid plus the element's hash: stable for the window's lifetime, unlike its title.
    static func identity(of window: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return "\(pid):\(CFHash(window))"
    }
}

/// An AXUIElement crossing a task boundary. The C API is thread-safe; Swift just can't prove it.
struct SendableElement: @unchecked Sendable {
    let element: AXUIElement
}
