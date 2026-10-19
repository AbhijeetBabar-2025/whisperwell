import XCTest
@testable import WhisperwellCore

final class FocusKindTests: XCTestCase {
    func testTextRolesAreEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(FocusKind.classify(role: role, valueSettable: false), .editable, role)
        }
    }

    func testSettableValueMakesUnclearRolesEditable() {
        XCTAssertEqual(FocusKind.classify(role: "AXWebArea", valueSettable: true), .editable)
        XCTAssertEqual(FocusKind.classify(role: nil, valueSettable: true), .editable)
    }

    func testControlsThatCantTakeTextAreNotEditable() {
        for role in ["AXButton", "AXLink", "AXCheckBox", "AXImage", "AXWindow", "AXApplication"] {
            XCTAssertEqual(FocusKind.classify(role: role, valueSettable: false), .notEditable, role)
        }
        // A settable value doesn't make a slider or checkbox a place for text.
        XCTAssertEqual(FocusKind.classify(role: "AXSlider", valueSettable: true), .notEditable)
    }

    func testUnclearRolesAreUnknownSoPasteIsStillTried() {
        // Spreadsheet cells and tables accept ⌘V without a text cursor; web pages and missing info are unclear.
        for role in ["AXTable", "AXCell", "AXGroup", "AXWebArea", "AXScrollArea"] {
            XCTAssertEqual(FocusKind.classify(role: role, valueSettable: false), .unknown, role)
        }
        XCTAssertEqual(FocusKind.classify(role: nil, valueSettable: false), .unknown)
    }
}

final class FieldStateTests: XCTestCase {
    func testChangedFieldMeansInsertionLanded() {
        let before = FieldState(characterCount: 10, selectionLocation: 10, selectionLength: 0)
        XCTAssertEqual(FieldState.landed(before: before, after: FieldState(characterCount: 15, selectionLocation: 15, selectionLength: 0)), true)
    }

    func testReplacingSelectionWithSameLengthStillCounts() {
        let before = FieldState(characterCount: 10, selectionLocation: 0, selectionLength: 5)
        XCTAssertEqual(FieldState.landed(before: before, after: FieldState(characterCount: 10, selectionLocation: 5, selectionLength: 0)), true)
    }

    func testUnchangedFieldMeansInsertionWasBlocked() {
        let state = FieldState(characterCount: 10, selectionLocation: 3, selectionLength: 0)
        XCTAssertEqual(FieldState.landed(before: state, after: state), false)
    }

    func testUnreadableFieldIsUnknown() {
        let state = FieldState(characterCount: 10, selectionLocation: 3, selectionLength: 0)
        XCTAssertNil(FieldState.landed(before: nil, after: state))
        XCTAssertNil(FieldState.landed(before: state, after: nil))
    }
}

final class KeystrokeTests: XCTestCase {
    func testOneKeystrokePerCharacter() {
        XCTAssertEqual(Keystroke.plan(for: "Hi!"), [.text("H"), .text("i"), .text("!")])
    }

    func testKeepsEmojiAndAccentsWhole() {
        XCTAssertEqual(Keystroke.plan(for: "é👍🏽"), [.text("é"), .text("👍🏽")])
    }

    func testNewlinesBecomeReturnKey() {
        XCTAssertEqual(Keystroke.plan(for: "a\nb\r\nc"), [.text("a"), .returnKey, .text("b"), .returnKey, .text("c")])
    }
}
