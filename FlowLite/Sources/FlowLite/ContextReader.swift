import AppKit
import ApplicationServices
import FlowLiteCore

/// Reads the frontmost app and the focused text field through the Accessibility API.
/// Needs Accessibility permission; without it only the app name is filled in.
enum ContextReader {
    static func current() -> TextContext {
        let app = NSWorkspace.shared.frontmostApplication
        var context = TextContext(appName: app?.localizedName, bundleID: app?.bundleIdentifier)

        let systemWide = AXUIElementCreateSystemWide()
        // Don't let a hung app stall dictation start.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        guard let focused = element(systemWide, kAXFocusedUIElementAttribute) else { return context }

        if let subrole = attribute(focused, kAXSubroleAttribute) as? String,
           subrole == kAXSecureTextFieldSubrole {
            context.isSecureField = true
            return context
        }
        guard let value = attribute(focused, kAXValueAttribute) as? String else { return context }

        var range = CFRange(location: (value as NSString).length, length: 0)
        if let raw = attribute(focused, kAXSelectedTextRangeAttribute),
           CFGetTypeID(raw) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cfRange, &range)
        }
        context.setFieldValue(value, selectionLocation: range.location, selectionLength: range.length)
        return context
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = attribute(parent, name), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }
}
