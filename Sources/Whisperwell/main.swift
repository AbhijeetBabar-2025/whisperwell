import AppKit
import WhisperwellCore

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
        let about = NSMenuItem(title: "About Whisperwell", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let openConfig = NSMenuItem(title: "Open Config File", action: #selector(openConfig), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)
        menu.addItem(NSMenuItem(title: "Quit Whisperwell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
                           status: "Microphone blocked. Allow Whisperwell in System Settings › Privacy & Security › Microphone.")
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
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Whisperwell")
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
                try encoder.encode(Config()).write(to: url)
                // Keys typed into this file are moved to the Keychain at next launch; keep it private meanwhile.
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

// Before anything reads the config: pick up settings and models saved under the old name.
do {
    try LegacyMigration.run()
} catch {
    log.error("\(String(describing: error), privacy: .public)")
    fputs("warning: \(error)\n", stderr)
}
// API keys belong in the Keychain; move any left in the settings file by older versions or typed in by hand.
do {
    if try Config.moveKeysToKeychain() { log.info("Moved API keys from the settings file to the Keychain") }
} catch {
    log.error("Couldn't move API keys to the Keychain: \(error.localizedDescription, privacy: .public)")
    fputs("warning: couldn't move API keys to the Keychain: \(error.localizedDescription). They stay in the settings file for now.\n", stderr)
}

// Command-line test mode: Whisperwell --transcribe <audio file>
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--transcribe") {
    guard flag + 1 < arguments.count else {
        fputs("usage: Whisperwell --transcribe <audio file>\n", stderr)
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

// Test inserting without dictating: Whisperwell --insert-test "<text>" [--into <app name>] waits 3 s for you to
// focus a field, inserts the text there the way a dictation would, and prints what happened.
// Launch it with `open -n Whisperwell.app --args …` so macOS applies the app's own Accessibility permission.
if let flag = arguments.firstIndex(of: "--insert-test"), flag + 1 < arguments.count {
    print("accessibility: \(Permissions.accessibility(prompt: false))")
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        let field = FocusedField.current()
        // --into <app name>: insert only if that app is frontmost, so a stray focus change can't misfire.
        if let into = arguments.firstIndex(of: "--into").flatMap({ $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }),
           field.appName != into {
            print("skipped: \(field.appName ?? "?") is frontmost, not \(into)")
            exit(1)
        }
        print("app: \(field.appName ?? "?"), role: \(field.role ?? "?"), focus: \(field.kind), secure: \(field.isSecure), state: \(String(describing: field.state()))")
        TextInserter.insert(arguments[flag + 1], into: field) { outcome in
            print("outcome: \(outcome)")
            // Stay until the clipboard is restored, as the running app would.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
        }
    }
    RunLoop.main.run()
}

// main.swift runs on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
