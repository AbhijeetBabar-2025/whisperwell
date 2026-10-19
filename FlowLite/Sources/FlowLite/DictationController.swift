import Foundation
import FlowLiteCore
import os

let log = Logger(subsystem: "local.flowlite", category: "dictation")

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

    /// Ignore taps shorter than this; they're usually accidental.
    private static let minimumDuration: TimeInterval = 0.3

    private let config: Config
    private let onDevice: OnDeviceTranscriber?
    private let feedback: Feedback
    private let recorder = AudioRecorder()
    private var context = TextContext()
    private var startedAt = Date()
    private var previewTask: Task<Void, Never>?
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
        // Start the mic first so the first words aren't clipped, then read the target field
        // (an Accessibility call that can take a moment) before focus can move.
        do {
            try recorder.start()
        } catch {
            fail(error)
            return
        }
        startedAt = Date()
        state = .recording
        feedback.recordingRequested()
        context = ContextReader.current()
        startLivePreview()
    }

    /// While the hotkey is held, re-transcribe the audio so far and show it in the indicator.
    /// Runs one pass at a time, so a slow Mac just updates less often.
    private func startLivePreview() {
        guard config.livePreview, config.showIndicator, let onDevice else { return }
        previewTask = Task { [weak self] in
            var passes = 0
            var totalMs = 0
            defer {
                if passes > 0 {
                    log.info("Live preview: \(passes, privacy: .public) passes, \(totalMs / passes, privacy: .public) ms average")
                }
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(LivePreview.interval * 1_000_000_000))
                guard let self, !Task.isCancelled, self.state == .recording else { return }
                let samples = self.recorder.snapshot()
                guard samples.count >= AudioFormat.sampleRate else { continue } // wait for 1 s of audio
                let recent = Array(samples.suffix(LivePreview.maxSeconds * AudioFormat.sampleRate))
                let passStart = Date()
                let text = try? await onDevice.transcribe(samples: recent)
                passes += 1
                totalMs += Int(Date().timeIntervalSince(passStart) * 1000)
                guard let text,
                      !Task.isCancelled, self.state == .recording, !text.isEmpty else { continue }
                self.feedback.partial(LivePreview.tail(text))
            }
        }
    }

    private func stopLivePreview() {
        previewTask?.cancel()
        previewTask = nil
    }

    func cancel() {
        guard state == .recording else { return }
        stopLivePreview()
        _ = recorder.stop()
        log.info("Dictation cancelled: another key was pressed while the hotkey was held")
        feedback.cancelled()
        state = .idle
    }

    func finish() {
        guard state == .recording else { return }
        stopLivePreview()
        let samples = recorder.stop()
        let duration = Date().timeIntervalSince(startedAt)
        guard duration >= Self.minimumDuration, !samples.isEmpty else {
            feedback.cancelled()
            state = .idle
            return
        }
        state = .processing
        feedback.transcribing()

        let onDeviceTranscribe: DictationPipeline.Transcribe? = onDevice.map { transcriber in
            { @Sendable samples in try await transcriber.transcribe(samples: samples) }
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
                log.info("Speech-to-text heard \(result.raw.count, privacy: .public) characters; pasting \(result.text.count, privacy: .public) after cleanup")
                deliver(result.text, into: context)
            } catch {
                fail(error)
            }
        }
    }

    private func micStarted() {
        guard state == .recording else { return }
        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        log.info("Mic capturing \(ms, privacy: .public) ms after the hotkey")
        feedback.listening()
    }

    private func deliver(_ text: String, into context: TextContext) {
        guard !text.isEmpty else {
            log.info("Nothing to insert (empty transcript)")
            feedback.notice("Didn't catch that. Try again.")
            state = .idle
            return
        }
        if context.isSecureField {
            fail(InsertError.secureField)
            return
        }
        guard Permissions.accessibility(prompt: false) else {
            // Don't lose the dictation: hand it over through the clipboard.
            TextInserter.copy(text)
            fail(InsertError.noAccessibility, notice: "Copied to clipboard. Press ⌘V to paste.")
            return
        }
        TextInserter.insert(text)
        feedback.inserted()
        log.info("Inserted \(text.count, privacy: .public) characters into \(context.appName ?? "unknown app", privacy: .public)")
        state = .idle
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

    var errorDescription: String? {
        switch self {
        case .secureField:
            return "Not pasting into a password field."
        case .noAccessibility:
            return "Couldn't paste, so your text is on the clipboard: press ⌘V. To paste automatically, allow FlowLite under System Settings › Privacy & Security › Accessibility, then relaunch it."
        }
    }
}
