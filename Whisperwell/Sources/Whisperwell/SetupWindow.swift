import AppKit
import AVFoundation
import WhisperwellCore
import SwiftUI

/// First-run setup: a live checklist of the permissions Whisperwell needs, each with a button to
/// the right page in System Settings. Shown at launch while anything is missing.
@MainActor
final class SetupWindowController {
    private var window: NSWindow?
    let model: SetupModel

    init(hotkey: HotkeyChoice) {
        model = SetupModel(hotkey: hotkey)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SetupView(model: model)))
            window.title = "Set Up Whisperwell"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.startRefreshing()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// For `--render-setup`: the window's content, laid out but not shown.
    static func makeView() -> NSView {
        NSHostingView(rootView: SetupView(model: SetupModel(hotkey: .rightOption)))
    }
}

@MainActor
final class SetupModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let title: String
        let why: String
        var granted: Bool
    }

    let hotkey: HotkeyChoice
    @Published var items: [Item] = []
    @Published var speechStatus = "Speech model: loading…"
    private var timer: Timer?

    init(hotkey: HotkeyChoice) {
        self.hotkey = hotkey
        refresh()
    }

    var allGranted: Bool { items.allSatisfy(\.granted) }

    func startRefreshing() {
        timer?.invalidate()
        // macOS doesn't announce permission changes, so poll while the window is open.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let missing = Set(Permissions.missing().map(\.name))
        items = [
            Item(id: "Microphone", title: "Microphone", why: "Hears you while you hold the hotkey.",
                 granted: !missing.contains("Microphone")),
            Item(id: "Input Monitoring", title: "Input Monitoring", why: "Notices the hotkey in any app. Restart Whisperwell after allowing.",
                 granted: !missing.contains("Input Monitoring")),
            Item(id: "Accessibility", title: "Accessibility", why: "Reads the text around your cursor and pastes the result.",
                 granted: !missing.contains("Accessibility")),
        ]
    }

    func allow(_ id: String) {
        if id == "Microphone", AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Permissions.microphone { [weak self] _ in self?.refresh() }
            return
        }
        if let url = Permissions.missing().first(where: { $0.name == id })?.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    private let mint = Color(red: 0.07, green: 0.64, blue: 0.48)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Whisperwell").font(.title2.weight(.semibold))
                    Text("Allow these so Whisperwell can hear you and type for you.")
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(model.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.granted ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(item.granted ? mint : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.body.weight(.medium))
                            Text(item.why).font(.callout).foregroundColor(.secondary)
                        }
                        Spacer()
                        if !item.granted {
                            Button("Allow…") { model.allow(item.id) }
                        }
                    }
                    .padding(.vertical, 10)
                    if item.id != model.items.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            Text(model.speechStatus).font(.callout).foregroundColor(.secondary)

            if model.allGranted {
                Text("You're all set. Click into any text field, hold \(model.hotkey.displayName), speak, and let go.")
                    .font(.callout.weight(.medium))
            }

            HStack {
                Button("Restart Whisperwell") { AppRestarter.restart() }
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
