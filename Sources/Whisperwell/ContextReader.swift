import AppKit
import ApplicationServices
import WhisperwellCore

/// Reads the frontmost app and the focused text field through the Accessibility API.
/// Needs Accessibility permission; without it only the app name is filled in.
enum ContextReader {
    static func current() -> TextContext {
        let app = NSWorkspace.shared.frontmostApplication
        if let app { exposeElectronFields(app) }
        var context = TextContext(appName: app?.localizedName, bundleID: app?.bundleIdentifier)

        guard let focused = focusedElement(in: app) else { return context }

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

    /// Asks the frontmost app for its focused element. The system-wide query often fails with
    /// "cannot complete" (-25204) even when the app answers fine, so it's only the fallback.
    fileprivate static func focusedElement(in app: NSRunningApplication?) -> AXUIElement? {
        var sources: [AXUIElement] = []
        if let app { sources.append(AXUIElementCreateApplication(app.processIdentifier)) }
        sources.append(AXUIElementCreateSystemWide())
        for source in sources {
            // Don't let a hung app stall dictation.
            AXUIElementSetMessagingTimeout(source, 0.25)
            if let focused = element(source, kAXFocusedUIElementAttribute) { return focused }
        }
        return nil
    }

    fileprivate static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    fileprivate static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = attribute(parent, name), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static var exposedPIDs = Set<pid_t>()

    /// Electron apps (VS Code, Slack, Discord, Notion…) hide their text fields from Accessibility
    /// until a tool asks for them with `AXManualAccessibility`. Asked once per app launch; the
    /// first dictation into a newly opened app may still go without context.
    private static func exposeElectronFields(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard !exposedPIDs.contains(pid), let bundle = app.bundleURL else { return }
        exposedPIDs.insert(pid)
        let electron = bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        guard FileManager.default.fileExists(atPath: electron.path) else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        let result = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        log.info("Asked \(app.localizedName ?? "an Electron app", privacy: .public) to expose its text fields: AX result \(result.rawValue, privacy: .public)")
    }
}

/// Whatever has keyboard focus right before inserting. Read again at that point (not only when the
/// hotkey went down) so the text follows focus changes made while the dictation was processing.
struct FocusedField {
    let element: AXUIElement?
    let role: String?
    let kind: FocusKind
    let isSecure: Bool
    let appName: String?

    static func current() -> FocusedField {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName
        guard let focused = ContextReader.focusedElement(in: app) else {
            return FocusedField(element: nil, role: nil, kind: .unknown, isSecure: false, appName: appName)
        }
        let subrole = ContextReader.attribute(focused, kAXSubroleAttribute) as? String
        var settable: DarwinBoolean = false
        let valueSettable = AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
        let role = ContextReader.attribute(focused, kAXRoleAttribute) as? String
        let kind = FocusKind.classify(role: role, valueSettable: valueSettable)
        return FocusedField(element: focused, role: role, kind: kind,
                            isSecure: subrole == kAXSecureTextFieldSubrole, appName: appName)
    }

    /// The field's length and selection, or nil if the app doesn't report them.
    func state() -> FieldState? {
        guard let element, let range = Self.selection(of: element) else { return nil }
        let count: Int
        if let number = ContextReader.attribute(element, kAXNumberOfCharactersAttribute) as? Int {
            count = number
        } else if let value = ContextReader.attribute(element, kAXValueAttribute) as? String {
            count = (value as NSString).length
        } else {
            return nil
        }
        return FieldState(characterCount: count, selectionLocation: range.location, selectionLength: range.length)
    }

    private static func selection(of element: AXUIElement) -> CFRange? {
        guard let raw = ContextReader.attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
