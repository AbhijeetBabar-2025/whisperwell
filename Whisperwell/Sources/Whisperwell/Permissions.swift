import AVFoundation
import ApplicationServices
import CoreGraphics

enum Permissions {
    /// Needed to read the focused text field and to post ⌘V.
    @discardableResult
    static func accessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Needed for the keyboard event tap.
    @discardableResult
    static func inputMonitoring(request: Bool) -> Bool {
        if CGPreflightListenEventAccess() { return true }
        return request ? CGRequestListenEventAccess() : false
    }

    /// Permissions that are currently missing, with the System Settings page that grants each.
    static func missing() -> [(name: String, settingsURL: URL)] {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        var result: [(String, URL)] = []
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            result.append(("Microphone", URL(string: base + "Privacy_Microphone")!))
        }
        if !CGPreflightListenEventAccess() {
            result.append(("Input Monitoring", URL(string: base + "Privacy_ListenEvent")!))
        }
        if !accessibility(prompt: false) {
            result.append(("Accessibility", URL(string: base + "Privacy_Accessibility")!))
        }
        return result
    }

    static func microphone(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }
}
