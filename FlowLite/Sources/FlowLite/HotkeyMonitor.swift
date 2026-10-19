import CoreGraphics
import Foundation
import FlowLiteCore

/// Watches a single modifier key system-wide with a listen-only CGEventTap.
/// Needs Input Monitoring permission. Callbacks fire on the main thread.
final class HotkeyMonitor {
    var onPress: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?
    /// Another key went down while the hotkey was held (for example Option+e to type an accent).
    var onOtherKey: (@MainActor () -> Void)?

    private let keyCode: Int64
    private let flag: CGEventFlags
    private var tap: CFMachPort?
    private var isDown = false

    init(hotkey: HotkeyChoice) {
        switch hotkey {
        case .rightOption: keyCode = 61; flag = .maskAlternate
        case .rightCommand: keyCode = 54; flag = .maskCommand
        case .fn: keyCode = 63; flag = .maskSecondaryFn
        }
    }

    func start() throws {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap's run loop source is on the main run loop, so this is the main thread.
                MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyError.tapCreationFailed
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    @MainActor
    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns off taps that respond slowly; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return }
            let down = event.flags.contains(flag)
            if down, !isDown {
                isDown = true
                onPress?()
            } else if !down, isDown {
                isDown = false
                onRelease?()
            }
        case .keyDown:
            if isDown { onOtherKey?() }
        default:
            break
        }
    }
}

enum HotkeyError: LocalizedError {
    case tapCreationFailed

    var errorDescription: String? {
        "Couldn't watch the keyboard. Allow FlowLite under System Settings › Privacy & Security › Input Monitoring, then relaunch it."
    }
}
