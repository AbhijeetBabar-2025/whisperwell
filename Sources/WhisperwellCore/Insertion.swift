import Foundation

/// What has keyboard focus when it's time to insert, judged from its Accessibility attributes.
public enum FocusKind: Equatable, Sendable {
    /// A text field or text area. Only here is it safe to type keystrokes when ⌘V is ignored.
    case editable
    /// A button, link, image, or bare window: ⌘V would do nothing there.
    case notEditable
    /// Not enough information (common in Electron apps, games, spreadsheets, and web pages): paste
    /// anyway, but never type, since keystrokes there can press buttons or trigger shortcuts.
    case unknown

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    // Only roles that can't take pasted text. Tables, cells, and web areas stay unknown
    // because spreadsheets and some web editors accept ⌘V without a text cursor.
    private static let nonTextRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXMenuItem", "AXSlider", "AXImage", "AXWindow", "AXApplication",
    ]

    /// A text cursor alone isn't enough: Chrome reports one on focused buttons too.
    public static func classify(role: String?, valueSettable: Bool) -> FocusKind {
        guard let role else { return valueSettable ? .editable : .unknown }
        if textRoles.contains(role) { return .editable }
        if nonTextRoles.contains(role) { return .notEditable }
        return valueSettable ? .editable : .unknown
    }
}

/// The parts of a text field that change when text lands in it. Ranges are in UTF-16 units, as Accessibility reports them.
public struct FieldState: Equatable, Sendable {
    public var characterCount: Int
    public var selectionLocation: Int
    public var selectionLength: Int

    public init(characterCount: Int, selectionLocation: Int, selectionLength: Int) {
        self.characterCount = characterCount
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
    }

    /// Whether inserting text changed the field: `nil` when either reading failed, so there's no way to tell.
    public static func landed(before: FieldState?, after: FieldState?) -> Bool? {
        guard let before, let after else { return nil }
        return before != after
    }
}

/// One key event when typing text instead of pasting it.
public enum Keystroke: Equatable, Sendable {
    case text(String)
    case returnKey

    /// One event per character (some apps read only the first character of a multi-character event).
    /// Newlines become the Return key, since many apps ignore a typed "\n".
    public static func plan(for text: String) -> [Keystroke] {
        text.map { $0.isNewline ? .returnKey : .text(String($0)) }
    }
}
