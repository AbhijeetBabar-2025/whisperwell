import Foundation

/// Audio in, text out: transcribe, then optionally clean up.
/// If cleanup fails, the raw transcript is used so a dictation is never lost.
public struct DictationPipeline: Sendable {
    public typealias Transcribe = @Sendable ([Int16]) async throws -> String
    public typealias Clean = @Sendable (String) async throws -> String
    public typealias Log = @Sendable (String) -> Void

    let transcribe: Transcribe
    let clean: Clean?
    let log: Log

    public init(transcribe: @escaping Transcribe, clean: Clean?, log: @escaping Log = { _ in }) {
        self.transcribe = transcribe
        self.clean = clean
        self.log = log
    }

    /// Wires the speech-to-text and cleanup steps from config.
    /// `onDevice` is the WhisperKit transcriber, which lives in the app target.
    public static func make(
        config: Config,
        context: TextContext,
        transport: HTTPTransport = URLSessionTransport(),
        onDevice: Transcribe? = nil,
        log: @escaping Log = { _ in }
    ) throws -> DictationPipeline {
        let transcribe: Transcribe
        switch config.asrProvider {
        case .whisperkit:
            guard let onDevice else { throw ConfigError.onDeviceSpeechUnavailable }
            transcribe = onDevice
        case .api:
            let transcriber = try Transcriber(config: config, transport: transport)
            let vocabulary = config.dictionary
            transcribe = { samples in
                let wav = WAVEncoder.encode(samples: samples, sampleRate: AudioFormat.sampleRate)
                return try await transcriber.transcribe(wav: wav, vocabulary: vocabulary)
            }
        }
        var clean: Clean?
        if config.cleanupEnabled {
            let dictionary = config.dictionary
            do {
                switch config.cleanupProvider {
                case .anthropic:
                    let cleaner = try Cleaner(config: config, transport: transport)
                    clean = { raw in
                        CleanupPrompt.removingEchoedContext(
                            try await cleaner.clean(transcript: raw, context: context, dictionary: dictionary),
                            textBefore: context.textBefore)
                    }
                case .local:
                    let cleaner = try LocalCleaner(config: config, transport: transport)
                    clean = { raw in
                        CleanupPrompt.removingEchoedContext(
                            try await cleaner.clean(transcript: raw, context: context, dictionary: dictionary),
                            textBefore: context.textBefore)
                    }
                }
            } catch {
                log("Cleanup is off for this dictation: \(error.localizedDescription)")
            }
        }
        if let fullClean = clean {
            let maxWords = config.skipCleanupMaxWords
            clean = { raw in
                guard ShortPhrase.canSkipCleanup(raw, maxWords: maxWords) else { return try await fullClean(raw) }
                log("Short phrase: pasted without cleanup")
                return ShortPhrase.fitted(raw, textBefore: context.textBefore)
            }
        }
        return DictationPipeline(transcribe: transcribe, clean: clean, log: log)
    }

    public struct Result: Equatable, Sendable {
        /// What speech-to-text heard.
        public let raw: String
        /// What gets pasted: the cleaned-up text, or `raw` if cleanup is off or failed.
        public let text: String
        /// How long each step took, for the log.
        public var transcribeSeconds: Double = 0
        public var cleanupSeconds: Double = 0

        public init(raw: String, text: String, transcribeSeconds: Double = 0, cleanupSeconds: Double = 0) {
            self.raw = raw
            self.text = text
            self.transcribeSeconds = transcribeSeconds
            self.cleanupSeconds = cleanupSeconds
        }

        /// Compares the text only; timings differ on every run.
        public static func == (a: Result, b: Result) -> Bool {
            a.raw == b.raw && a.text == b.text
        }
    }

    /// `samples` are 16 kHz mono 16-bit PCM.
    public func run(samples: [Int16]) async throws -> String {
        try await runDetailed(samples: samples).text
    }

    public func runDetailed(samples: [Int16]) async throws -> Result {
        let start = Date()
        let raw = try await transcribe(samples)
        let transcribed = Date()
        let transcribeSeconds = transcribed.timeIntervalSince(start)
        guard let clean, !raw.isEmpty else { return Result(raw: raw, text: raw, transcribeSeconds: transcribeSeconds) }
        var text = raw
        do {
            text = try await clean(raw)
        } catch {
            log("Cleanup failed, using the raw transcript instead: \(error.localizedDescription)")
        }
        return Result(raw: raw, text: text, transcribeSeconds: transcribeSeconds,
                      cleanupSeconds: Date().timeIntervalSince(transcribed))
    }
}
