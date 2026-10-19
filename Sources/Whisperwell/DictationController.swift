import Foundation
import WhisperwellCore
import os

let log = Logger(subsystem: "local.whisperwell", category: "dictation")

/// Hold the hotkey to record; release to transcribe, clean up, and paste.
@MainActor
final class DictationController {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    /// The hotkey must be held this long before dictation shows itself. Shorter taps, and Option
    /// shortcuts typed within this time, are dropped silently.
    private static let holdDelay: TimeInterval = 0.3

    private let config: Config
    private let onDevice: OnDeviceTranscriber?
    private let feedback: Feedback
    private let recorder = AudioRecorder()
    private var context = TextContext()
    private var startedAt = Date()
    /// The mic is running but the hotkey hasn't been held for `holdDelay` yet.
    private var holdPending = false
    private var holdWork: DispatchWorkItem?
    private var micCapturing = false
    private var previewTask: Task<Void, Never>?
    /// Transcribes the recording in pieces while the hotkey is held (on-device speech only).
    private var incremental: IncrementalTranscript?
    /// What speech-to-text heard last time, before cleanup. Offered in the menu.
    private(set) var lastRawTranscript: String?

    init(config: Config, onDevice: OnDeviceTranscriber?, feedback: Feedback) {
        self.config = config
        self.onDevice = onDevice
        self.feedback = feedback
        recorder.onFirstAudio = { [weak self] in self?.micStarted() }
        recorder.onLevel = { [weak feedback] level in feedback?.level(level) }
        recorder.warmUp()
    }

    func begin() {
        switch state {
        case .recording, .processing: return
        case .idle, .failed: break
        }
        guard !holdPending else { return }
        // Start the mic first so the first words aren't clipped, then read the target field
        // (an Accessibility call that can take a moment) before focus can move. Nothing is shown
        // or played until the hotkey has been held for `holdDelay`.
        do {
            try recorder.start()
        } catch {
            fail(error)
            return
        }
        startedAt = Date()
        micCapturing = false
        holdPending = true
        context = ContextReader.current()
        let work = DispatchWorkItem { [weak self] in self?.holdConfirmed() }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
    }

    /// Held long enough: this is a dictation.
    private func holdConfirmed() {
        guard holdPending else { return }
        holdPending = false
        holdWork = nil
        state = .recording
        feedback.recordingRequested()
        if micCapturing { feedback.listening() }
        startLiveTranscription()
    }

    /// Released (or another key pressed) before `holdDelay`: drop the audio without any sound or indicator.
    private func dropPendingHold(_ reason: String) {
        holdWork?.cancel()
        holdWork = nil
        holdPending = false
        _ = recorder.stop()
        log.info("Ignored: \(reason, privacy: .public) within \(Int(Self.holdDelay * 1000), privacy: .public) ms of the hotkey")
    }

    /// While the hotkey is held, transcribe finished parts of the recording (cut at pauses), so
    /// releasing only has to transcribe the last few seconds. With live preview on, the passes in
    /// between also show the words so far in the indicator. One pass at a time, so a slow Mac
    /// just updates less often.
    private func startLiveTranscription() {
        guard let onDevice else { return }
        let showPreview = config.livePreview && config.showIndicator
        let incremental = IncrementalTranscript { samples in try await onDevice.transcribe(samples: samples) }
        self.incremental = incremental
        previewTask = Task { [weak self] in
            var passes = 0
            var totalMs = 0
            defer {
                if passes > 0 {
                    log.info("Live transcription: \(passes, privacy: .public) passes, \(totalMs / passes, privacy: .public) ms average")
                }
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(LivePreview.interval * 1_000_000_000))
                guard let self, !Task.isCancelled, self.state == .recording else { return }
                let samples = self.recorder.snapshot()
                guard samples.count >= AudioFormat.sampleRate else { continue } // wait for 1 s of audio
                let passStart = Date()
                guard let text = await incremental.update(samples: samples, preview: showPreview) else { continue }
                passes += 1
                totalMs += Int(Date().timeIntervalSince(passStart) * 1000)
                guard showPreview, !Task.isCancelled, self.state == .recording, !text.isEmpty else { continue }
                self.feedback.partial(LivePreview.tail(text))
            }
        }
    }

    /// Stops starting new passes. A pass already running finishes; `IncrementalTranscript.finish` decides what to keep.
    private func stopLiveTranscription() {
        previewTask?.cancel()
        previewTask = nil
    }

    func cancel() {
        if holdPending { return dropPendingHold("another key was pressed") }
        guard state == .recording else { return }
        stopLiveTranscription()
        _ = recorder.stop()
        incremental = nil
        log.info("Dictation cancelled: another key was pressed while the hotkey was held")
        feedback.cancelled()
        state = .idle
    }

    func finish() {
        if holdPending { return dropPendingHold("the hotkey was released") }
        guard state == .recording else { return }
        stopLiveTranscription()
        let samples = recorder.stop()
        let duration = Date().timeIntervalSince(startedAt)
        guard !samples.isEmpty else {
            feedback.cancelled()
            state = .idle
            return
        }
        state = .processing
        feedback.transcribing()

        var onDeviceTranscribe: DictationPipeline.Transcribe? = onDevice.map { transcriber in
            { @Sendable samples in try await transcriber.transcribe(samples: samples) }
        }
        if let incremental {
            // Most of the recording is already transcribed; this only does what's left.
            onDeviceTranscribe = { @Sendable samples in
                let done = await incremental.committedSeconds
                log.info("\(String(format: "%.1f", done), privacy: .public)s of audio already transcribed at release (\(Pauses.summary(samples), privacy: .public))")
                return try await incremental.finish(samples: samples)
            }
            self.incremental = nil
        }
        let pipeline: DictationPipeline
        do {
            pipeline = try DictationPipeline.make(config: config, context: context, onDevice: onDeviceTranscribe) { message in
                log.warning("\(message, privacy: .public)")
            }
        } catch {
            fail(error)
            return
        }
        let context = self.context
        log.info("Transcribing \(String(format: "%.1f", duration), privacy: .public)s of audio")

        // The Task inherits the main actor; the network calls inside run() still don't block it.
        Task {
            do {
                let result = try await pipeline.runDetailed(samples: samples)
                lastRawTranscript = result.raw.isEmpty ? lastRawTranscript : result.raw
                // Lengths only: what you said is never logged.
                log.info("Speech-to-text heard \(result.raw.count, privacy: .public) characters in \(Int(result.transcribeSeconds * 1000), privacy: .public) ms; pasting \(result.text.count, privacy: .public) after \(Int(result.cleanupSeconds * 1000), privacy: .public) ms of cleanup")
                deliver(result.text, into: context)
            } catch {
                fail(error)
            }
        }
    }

    private func micStarted() {
        guard holdPending || state == .recording else { return }
        micCapturing = true
        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        log.info("Mic capturing \(ms, privacy: .public) ms after the hotkey")
        // While the hold is pending, the sound waits for `holdConfirmed`.
        if state == .recording { feedback.listening() }
    }

    private func deliver(_ text: String, into context: TextContext) {
        guard !text.isEmpty else {
            log.info("Nothing to insert (empty transcript)")
            feedback.notice("Didn't catch that. Try again.")
            state = .idle
            return
        }
        guard Permissions.accessibility(prompt: false) else {
            if context.isSecureField { return fail(InsertError.secureField) }
            // Don't lose the dictation: hand it over through the clipboard.
            TextInserter.copy(text)
            fail(InsertError.noAccessibility, notice: "Copied to clipboard. Press ⌘V to paste.")
            return
        }
        // Focus may have moved while processing; the text goes where it is now.
        let field = FocusedField.current()
        if context.isSecureField || field.isSecure {
            fail(InsertError.secureField)
            return
        }
        let appName = field.appName ?? context.appName ?? "unknown app"
        TextInserter.insert(text, into: field) { [self] outcome in
            switch outcome {
            case .pasted, .typed:
                let how = outcome == .typed ? "Typed (paste was ignored)" : "Inserted"
                log.info("\(how, privacy: .public) \(text.count, privacy: .public) characters into \(appName, privacy: .public)")
                feedback.inserted()
                state = .idle
            case .noTextField:
                fail(InsertError.noTextField, notice: "No text field selected. Copied: press ⌘V.")
            case .notConfirmed:
                fail(InsertError.notConfirmed, notice: "Couldn't insert here. Copied: press ⌘V.")
            }
        }
    }

    /// `notice` is a short version for the floating indicator; the menu shows the full message.
    private func fail(_ error: Error, notice: String? = nil) {
        let message = error.localizedDescription
        log.error("\(message, privacy: .public)")
        feedback.failed(notice ?? message)
        state = .failed(message)
    }
}

enum InsertError: LocalizedError {
    case secureField
    case noAccessibility
    case noTextField
    case notConfirmed

    var errorDescription: String? {
        switch self {
        case .secureField:
            return "Not pasting into a password field."
        case .noAccessibility:
            return "Couldn't paste, so your text is on the clipboard: press ⌘V. To paste automatically, allow Whisperwell under System Settings › Privacy & Security › Accessibility, then relaunch it."
        case .noTextField:
            return "Nothing that takes text was selected, so your text is on the clipboard: click into a text field and press ⌘V."
        case .notConfirmed:
            return "This field didn't accept pasted or typed text, so your text is on the clipboard: press ⌘V to try again, or paste it somewhere else."
        }
    }
}
