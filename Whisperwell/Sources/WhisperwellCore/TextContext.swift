import Foundation

/// What was on screen where the text will land, captured when the hotkey goes down.
public struct TextContext: Equatable, Sendable {
    public var appName: String?
    public var bundleID: String?
    public var textBefore = ""
    public var selectedText = ""
    public var textAfter = ""
    public var isSecureField = false

    public init(appName: String? = nil, bundleID: String? = nil) {
        self.appName = appName
        self.bundleID = bundleID
    }

    /// Splits a text field's value around its selection. Accessibility reports
    /// ranges in UTF-16 units, so this works on NSString and clamps bad ranges.
    public mutating func setFieldValue(_ value: String, selectionLocation: Int, selectionLength: Int) {
        let ns = value as NSString
        let location = min(max(0, selectionLocation), ns.length)
        let length = min(max(0, selectionLength), ns.length - location)
        textBefore = ns.substring(to: location)
        selectedText = ns.substring(with: NSRange(location: location, length: length))
        textAfter = ns.substring(from: location + length)
    }
}
