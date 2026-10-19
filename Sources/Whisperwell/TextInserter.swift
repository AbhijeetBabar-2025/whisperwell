import AppKit
import Carbon.HIToolbox
import CoreGraphics
import WhisperwellCore

/// Inserts text into whatever app has focus: put it on the clipboard, press ⌘V,
/// then put the user's previous clipboard back. Needs Accessibility permission to post keystrokes.
/// When the field reports its contents and ⌘V didn't change it (some web forms block pasting),
/// the text is typed as keystrokes instead.
enum TextInserter {
    enum Outcome {
        case pasted
        /// ⌘V was ignored, so the text was typed instead.
        case typed
        /// Focus is on something that can't take text; the text was left on the clipboard.
        case noTextField
        /// Neither pasting nor typing changed the field; the text was left on the clipboard.
        case notConfirmed
    }

    // Conventions clipboard managers honor: don't record or show this entry.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// The V key on a US layout, used when the current layout has no "v".
    private static let qwertyVKeyCode = CGKeyCode(kVK_ANSI_V)
    /// Slow apps may read the clipboard a moment after ⌘V; keep our text there at least this long.
    private static let clipboardHold: TimeInterval = 0.6
    /// When to look for the inserted text. A second look gives slow apps time before falling back.
    private static let checkDelays: [TimeInterval] = [0.3, 0.8]

    static func insert(_ text: String, into field: FocusedField, completion: @escaping (Outcome) -> Void) {
        if field.kind == .notEditable {
            copy(text)
            return completion(.noTextField)
        }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: concealedType)
        item.setData(Data(), forType: transientType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ourChangeCount = pasteboard.changeCount
        let pastedAt = Date()

        func restoreClipboard() {
            let wait = max(0, clipboardHold - Date().timeIntervalSince(pastedAt))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                // If something else wrote to the clipboard meanwhile, leave it alone.
                guard pasteboard.changeCount == ourChangeCount else { return }
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }

        // Only a known text field is checked (and typed into if ⌘V is ignored). Elsewhere,
        // keystrokes could press buttons or trigger shortcuts, so the paste is trusted.
        let before = field.kind == .editable ? field.state() : nil
        postCommandV()
        guard let before else {
            restoreClipboard()
            return completion(.pasted)
        }
        waitForChange(in: field, from: before) { pasted in
            // nil: the field stopped reporting (focus moved), so typing could land somewhere else.
            if pasted != false {
                restoreClipboard()
                return completion(.pasted)
            }
            type(text) {
                waitForChange(in: field, from: before) { typed in
                    if typed != false {
                        restoreClipboard()
                        return completion(.typed)
                    }
                    copy(text)
                    completion(.notConfirmed)
                }
            }
        }
    }

    /// Leaves the text on the clipboard for the user to paste, when Whisperwell can't paste it.
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Calls back with true as soon as the field differs from `before`, false if it never does, nil if it can't be read.
    private static func waitForChange(in field: FocusedField, from before: FieldState,
                                      delays: ArraySlice<TimeInterval> = checkDelays[...],
                                      elapsed: TimeInterval = 0, done: @escaping (Bool?) -> Void) {
        guard let delay = delays.first else { return done(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay - elapsed) {
            let landed = FieldState.landed(before: before, after: field.state())
            if landed != false || delays.count == 1 { return done(landed) }
            waitForChange(in: field, from: before, delays: delays.dropFirst(), elapsed: delay, done: done)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func postCommandV() {
        let key = keyCode(producing: "v") ?? qwertyVKeyCode
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        // Set flags explicitly so a still-held modifier doesn't turn this into another shortcut.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Types the text one character at a time, off the main thread so the indicator keeps drawing.
    private static func type(_ text: String, completion: @escaping () -> Void) {
        let strokes = Keystroke.plan(for: text)
        DispatchQueue.global(qos: .userInitiated).async {
            let source = CGEventSource(stateID: .combinedSessionState)
            for stroke in strokes {
                let key: CGKeyCode
                var units: [UniChar] = []
                switch stroke {
                case .returnKey: key = CGKeyCode(kVK_Return)
                case .text(let character):
                    key = 0
                    units = Array(character.utf16)
                }
                for isDown in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else { continue }
                    event.flags = []
                    if !units.isEmpty { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
                    event.post(tap: .cghidEventTap)
                }
                usleep(2_000) // Some apps drop characters that arrive faster than this.
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// The key that types `character` with ⌘ held in the current keyboard layout, so ⌘V works on
    /// Dvorak, AZERTY, and the like. Non-Latin layouts (Russian, Greek…) fall back to the user's
    /// Latin layout, which is what macOS uses for their shortcuts.
    private static func keyCode(producing character: String) -> CGKeyCode? {
        let layouts = [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource]
        for copyLayout in layouts {
            guard let source = copyLayout()?.takeRetainedValue(),
                  let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            let found: CGKeyCode? = data.withUnsafeBytes { bytes in
                guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                for code in 0..<128 {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown),
                                                UInt32((cmdKey >> 8) & 0xFF), UInt32(LMGetKbdType()),
                                                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                                &deadKeyState, chars.count, &length, &chars)
                    if status == noErr, String(utf16CodeUnits: chars, count: length).lowercased() == character {
                        return CGKeyCode(code)
                    }
                }
                return nil
            }
            if let found { return found }
        }
        return nil
    }
}
