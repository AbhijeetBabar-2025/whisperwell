import AppKit
import FlowLiteCore
import SwiftUI

/// Settings… window. Edits the same config file as before; saving restarts FlowLite to apply,
/// since the hotkey, speech model and indicator are all set up at launch.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let model = SettingsModel()
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "FlowLite Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// For `--render-settings`: the window's content view, laid out but not shown.
    static func makeView(tab: SettingsView.Tab) -> NSView {
        let model = SettingsModel()
        model.tab = tab
        return NSHostingView(rootView: SettingsView(model: model))
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config
    @Published var dictionaryText: String
    @Published var tab: SettingsView.Tab = .general
    @Published var connectionStatus = ""
    @Published var error = ""

    static let whisperModels = [
        ("large-v3-v20240930_626MB", "Large v3 Turbo, compressed (best accuracy, 600 MB)"),
        ("large-v3-v20240930_turbo", "Large v3 Turbo (fastest on Mac, 1.6 GB)"),
        ("small.en", "Small, English only (faster, 250 MB)"),
        ("small", "Small, multilingual (250 MB)"),
        ("base.en", "Base, English only (fastest, 75 MB)"),
    ]
    static let claudeModels = [
        ("claude-haiku-5-5", "Claude Haiku 5.5 (fast, low cost)"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-opus-5-5", "Claude Opus 5.5 (strongest rewrites, slower)"),
    ]

    init() {
        // Read the file itself, without environment-variable overrides, so saving
        // never copies a key from the shell into the file.
        let loaded = (try? Config.load(environment: [:])) ?? Config()
        config = loaded
        dictionaryText = loaded.dictionary.joined(separator: "\n")
    }

    func testConnection() {
        connectionStatus = "Testing…"
        var config = self.config
        config.cleanupProvider = .local
        Task {
            do {
                let model = try await LocalCleaner(config: config).checkServer()
                connectionStatus = "✓ Connected, using \(model)"
            } catch {
                connectionStatus = "⚠ \(error.localizedDescription)"
            }
        }
    }

    func saveAndRestart() {
        config.dictionary = dictionaryText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            try config.save()
        } catch {
            self.error = "Couldn't save settings: \(error.localizedDescription)"
            return
        }
        AppRestarter.restart()
    }
}

enum AppRestarter {
    /// Starts a fresh copy of FlowLite, then quits this one.
    @MainActor
    static func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    log.error("Restart failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}

struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general = "General", speech = "Speech", cleanup = "Cleanup", dictionary = "Dictionary"
    }

    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 20)

            Form {
                switch model.tab {
                case .general: general
                case .speech: speech
                case .cleanup: cleanup
                case .dictionary: dictionary
                }
            }
            .formStyle(.grouped)

            HStack {
                if !model.error.isEmpty {
                    Text(model.error).foregroundColor(.red).font(.callout)
                }
                Spacer()
                Button("Save and Restart FlowLite") { model.saveAndRestart() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
    }

    private var general: some View {
        Group {
            Section {
                Picker("Hold to dictate", selection: $model.config.hotkey) {
                    Text("Right Option ⌥").tag(HotkeyChoice.rightOption)
                    Text("Right Command ⌘").tag(HotkeyChoice.rightCommand)
                    Text("Fn").tag(HotkeyChoice.fn)
                }
                Toggle("Play sounds when listening starts and stops", isOn: $model.config.playSounds)
                Toggle("Show the floating indicator", isOn: $model.config.showIndicator)
                Toggle("Show words as you speak", isOn: $model.config.livePreview)
                    .disabled(!model.config.showIndicator || model.config.asrProvider != .whisperkit)
            }
            Section {
                Stepper(value: $model.config.skipCleanupMaxWords, in: 0...10) {
                    Text(model.config.skipCleanupMaxWords == 0
                         ? "Always clean up, even short phrases"
                         : "Skip cleanup for phrases up to \(model.config.skipCleanupMaxWords) words")
                }
                TextField("Language", text: Binding(
                    get: { model.config.language ?? "" },
                    set: { model.config.language = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Auto-detect (or a code like en)"))
            }
        }
    }

    private var speech: some View {
        Group {
            Section {
                Picker("Speech recognition", selection: $model.config.asrProvider) {
                    Text("On this Mac (free, private)").tag(SpeechProvider.whisperkit)
                    Text("Cloud API (OpenAI-compatible)").tag(SpeechProvider.api)
                }
            }
            if model.config.asrProvider == .whisperkit {
                Section {
                    Picker("Model", selection: $model.config.whisperModel) {
                        ForEach(SettingsModel.whisperModels, id: \.0) { Text($0.1).tag($0.0) }
                        if !SettingsModel.whisperModels.contains(where: { $0.0 == model.config.whisperModel }) {
                            Text(model.config.whisperModel).tag(model.config.whisperModel)
                        }
                    }
                    TextField("Custom model repo", text: optional(\.whisperModelRepo), prompt: Text("Optional, e.g. you/your-whisper"))
                    TextField("Model folder", text: optional(\.whisperModelFolder), prompt: Text("Optional, a model already on disk"))
                } footer: {
                    Text("A new model downloads the first time it's used.").font(.callout).foregroundColor(.secondary)
                }
            } else {
                Section {
                    TextField("Server URL", text: $model.config.asrBaseURL)
                    TextField("Model", text: $model.config.asrModel)
                    SecureField("API key", text: optional(\.asrAPIKey), prompt: Text("Not needed for a server on this Mac"))
                }
            }
        }
    }

    private var cleanup: some View {
        Group {
            Section {
                Toggle("Clean up text with AI", isOn: $model.config.cleanupEnabled)
                if model.config.cleanupEnabled {
                    Picker("Model runs on", selection: $model.config.cleanupProvider) {
                        Text("Your computer or local network").tag(CleanupProvider.local)
                        Text("Claude (Anthropic API)").tag(CleanupProvider.anthropic)
                    }
                }
            } footer: {
                Text("Removes filler words, applies corrections, and fixes punctuation. Without it, FlowLite pastes exactly what it heard.")
                    .font(.callout).foregroundColor(.secondary)
            }
            if model.config.cleanupEnabled && model.config.cleanupProvider == .local {
                Section {
                    TextField("Server URL", text: $model.config.localLLMBaseURL)
                    TextField("Model", text: $model.config.localLLMModel, prompt: Text("Blank uses the loaded model"))
                    SecureField("API key", text: optional(\.localLLMAPIKey), prompt: Text("Usually not needed"))
                    HStack {
                        Button("Test Connection") { model.testConnection() }
                        Text(model.connectionStatus).font(.callout).foregroundColor(.secondary).lineLimit(2)
                    }
                } footer: {
                    Text("LM Studio: http://127.0.0.1:1234/v1 · Ollama: http://localhost:11434/v1")
                        .font(.callout).foregroundColor(.secondary)
                }
            }
            if model.config.cleanupEnabled && model.config.cleanupProvider == .anthropic {
                Section {
                    SecureField("API key", text: optional(\.anthropicAPIKey), prompt: Text("sk-ant-…"))
                    Picker("Model", selection: $model.config.cleanupModel) {
                        ForEach(SettingsModel.claudeModels, id: \.0) { Text($0.1).tag($0.0) }
                        if !SettingsModel.claudeModels.contains(where: { $0.0 == model.config.cleanupModel }) {
                            Text(model.config.cleanupModel).tag(model.config.cleanupModel)
                        }
                    }
                }
            }
        }
    }

    private var dictionary: some View {
        Section {
            TextEditor(text: $model.dictionaryText)
                .font(.body)
                .frame(minHeight: 280)
        } header: {
            Text("Names, jargon, and acronyms, one per line")
        } footer: {
            Text("Used as spelling hints for speech recognition and cleanup.").font(.callout).foregroundColor(.secondary)
        }
    }

    /// Binds an optional string setting to a text field; an empty field means "not set".
    private func optional(_ path: WritableKeyPath<Config, String?>) -> Binding<String> {
        Binding(
            get: { model.config[keyPath: path] ?? "" },
            set: { model.config[keyPath: path] = $0.isEmpty ? nil : $0 }
        )
    }
}
