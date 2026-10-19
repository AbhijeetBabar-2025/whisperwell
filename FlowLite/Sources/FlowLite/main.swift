import AppKit
import FlowLiteCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let speechLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let cleanupLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionLine = NSMenuItem(title: "", action: #selector(openPermissionSettings), keyEquivalent: "")
    private var permissionURL: URL?
    private var onDevice: OnDeviceTranscriber?
    private var controller: DictationController?
    private var hotkey: HotkeyMonitor?
    private let settingsWindow = SettingsWindowController()
    private var setupWindow: SetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(speechLine)
        menu.addItem(cleanupLine)
        menu.addItem(permissionLine)
        permissionLine.target = self
        permissionLine.isHidden = true
        menu.delegate = self
        speechLine.isHidden = true
        cleanupLine.isHidden = true
        menu.addItem(.separator())
        let copyRaw = NSMenuItem(title: "Copy Last Raw Transcript", action: #selector(copyLastRaw), keyEquivalent: "")
        copyRaw.target = self
        menu.addItem(copyRaw)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About FlowLite", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let openConfig = NSMenuItem(title: "Open Config File", action: #selector(openConfig), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)
        menu.addItem(NSMenuItem(title: "Quit FlowLite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        show(symbol: "mic", status: "Starting…")

        let config: Config
        do {
            config = try Config.load()
        } catch {
            show(symbol: "exclamationmark.triangle", status: error.localizedDescription)
            return
        }
        speechLine.title = config.speechSummary
        speechLine.isHidden = false
        cleanupLine.title = config.cleanupSummary
        cleanupLine.isHidden = false
        checkLocalServer(config)
        let missing = Permissions.missing().map(\.name)
        log.info("Permissions missing at launch: \(missing.isEmpty ? "none" : missing.joined(separator: ", "), privacy: .public)")
        updatePermissionLine()
        let setup = SetupWindowController(hotkey: config.hotkey)
        setupWindow = setup
        if !missing.isEmpty { setup.show() }
        if config.asrProvider == .whisperkit {
            let summary = config.speechSummary
            let transcriber = OnDeviceTranscriber(config: config) { [weak self] status in
                Task { @MainActor in self?.showSpeech(status, summary: summary) }
            }
            onDevice = transcriber
            Task { await transcriber.prepare() }
        }

        Permissions.accessibility(prompt: true)
        Permissions.inputMonitoring(request: true)
        Permissions.microphone { [weak self] granted in
            if !granted {
                self?.show(symbol: "mic.slash",
                           status: "Microphone blocked. Allow FlowLite in System Settings › Privacy & Security › Microphone.")
            }
        }

        let feedback = Feedback(playSounds: config.playSounds, showIndicator: config.showIndicator)
        let controller = DictationController(config: config, onDevice: onDevice, feedback: feedback)
        controller.onStateChange = { [weak self] state in self?.render(state, hotkey: config.hotkey) }
        let monitor = HotkeyMonitor(hotkey: config.hotkey)
        monitor.onPress = { controller.begin() }
        monitor.onRelease = { controller.finish() }
        monitor.onOtherKey = { controller.cancel() }
        do {
            try monitor.start()
        } catch {
            show(symbol: "keyboard.badge.exclamationmark", status: error.localizedDescription)
            return
        }
        self.controller = controller
        hotkey = monitor
        render(.idle, hotkey: config.hotkey)
    }

    private func showSpeech(_ status: OnDeviceTranscriber.Status, summary: String) {
        setupWindow?.model.speechStatus = switch status {
        case .loading: "Speech model: loading. The first run downloads it, which can take a few minutes."
        case .ready: "Speech model: ready ✓"
        case let .failed(message): "Speech model: \(message)"
        }
        switch status {
        case .loading:
            speechLine.title = "\(summary) … loading (first run downloads it)"
            log.info("Loading on-device speech model")
        case .ready:
            speechLine.title = "\(summary) ✓ ready"
            log.info("On-device speech model ready")
        case let .failed(message):
            speechLine.title = "\(summary) ⚠ failed"
            speechLine.toolTip = message
            log.error("\(message, privacy: .public)")
        }
    }

    /// Contacts the local model server at launch so problems show up before the first dictation.
    private func checkLocalServer(_ config: Config) {
        guard config.cleanupEnabled, config.cleanupProvider == .local else { return }
        let summary = config.cleanupSummary
        Task { @MainActor in
            // Right after a new build launches, macOS can briefly block local-network access,
            // so retry once before reporting a problem.
            for attempt in 1...2 {
                do {
                    let model = try await LocalCleaner(config: config).checkServer()
                    log.info("Local model server OK, using \(model, privacy: .public)")
                    cleanupLine.title = "\(summary) ✓ connected"
                    cleanupLine.toolTip = nil
                    return
                } catch where attempt == 1 {
                    log.info("Local model check failed, retrying in 3 s: \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    log.error("Local model check failed: \(error.localizedDescription, privacy: .public)")
                    cleanupLine.title = "\(summary) ⚠ not reachable"
                    cleanupLine.toolTip = error.localizedDescription
                }
            }
        }
    }

    private func render(_ state: DictationController.State, hotkey: HotkeyChoice) {
        switch state {
        case .idle: show(symbol: "mic", status: "Ready. Hold \(hotkey.displayName) to dictate.")
        case .recording: show(symbol: "mic.fill", status: "Listening…")
        case .processing: show(symbol: "ellipsis.circle", status: "Transcribing…")
        case let .failed(message): show(symbol: "exclamationmark.triangle", status: message)
        }
    }

    private func show(symbol: String, status: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FlowLite")
        statusLine.title = status.count > 120 ? String(status.prefix(117)) + "…" : status
        statusLine.toolTip = status
    }

    /// Refresh the permission warning every time the menu opens, since the user may have just fixed it.
    func menuWillOpen(_ menu: NSMenu) {
        updatePermissionLine()
    }

    private func updatePermissionLine() {
        let missing = Permissions.missing()
        permissionURL = missing.first?.settingsURL
        permissionLine.isHidden = missing.isEmpty
        permissionLine.title = "⚠ Needs \(missing.map(\.name).joined(separator: ", ")). Click to set up"
    }

    @objc private func openPermissionSettings() {
        if let setupWindow {
            setupWindow.show()
        } else if let permissionURL {
            NSWorkspace.shared.open(permissionURL)
        }
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    /// What Whisper heard before cleanup, for when the cleaned-up text isn't what you said.
    @objc private func copyLastRaw() {
        guard let raw = controller?.lastRawTranscript else { return }
        TextInserter.copy(raw)
    }

    @objc private func showAbout() {
        // Menu bar apps aren't frontmost; bring the panel forward.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openConfig() {
        let url = Config.defaultURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                var starter = Config()
                starter.asrAPIKey = ""
                starter.anthropicAPIKey = ""
                try encoder.encode(starter).write(to: url)
                // The file holds API keys; keep it private to this user.
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                show(symbol: "exclamationmark.triangle", status: "Couldn't create \(url.path): \(error.localizedDescription)")
                return
            }
        }
        NSWorkspace.shared.open(url)
    }
}

extension HotkeyChoice {
    var displayName: String {
        switch self {
        case .rightOption: return "Right ⌥"
        case .rightCommand: return "Right ⌘"
        case .fn: return "Fn"
        }
    }
}

// Command-line test mode: FlowLite --transcribe <audio file>
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--transcribe") {
    guard flag + 1 < arguments.count else {
        fputs("usage: FlowLite --transcribe <audio file>\n", stderr)
        exit(2)
    }
    let before = arguments.firstIndex(of: "--before").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    exit(FileTranscription.run(path: arguments[flag + 1], textBefore: before ?? ""))
}

if let flag = arguments.firstIndex(of: "--render-indicator"), flag + 1 < arguments.count {
    exit(MainActor.assumeIsolated { IndicatorPreview.run(folder: arguments[flag + 1]) })
}

if let flag = arguments.firstIndex(of: "--render-ui"), flag + 1 < arguments.count {
    exit(MainActor.assumeIsolated { WindowPreview.run(folder: arguments[flag + 1]) })
}

// main.swift runs on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
