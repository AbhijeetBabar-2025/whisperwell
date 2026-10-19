import Foundation
import FlowLiteCore
// WhisperKit predates Swift's Sendable checking. The actor below runs one transcription at a
// time on it (see `transcribe`), since one WhisperKit instance can't decode two clips at once.
@preconcurrency import WhisperKit

/// Runs Whisper on this Mac with WhisperKit: free, offline, no API key.
/// The model downloads once (to Application Support), then loads from disk on each launch.
actor OnDeviceTranscriber {
    enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlowLite/Models", isDirectory: true)
    }

    private let config: Config
    private let onStatus: @Sendable (Status) -> Void
    private var kit: WhisperKit?
    private var loading: Task<Void, Error>?
    /// The most recent transcription job. Each new job waits for it, so jobs never overlap.
    private var lastJob: Task<String, Error>?

    init(config: Config, onStatus: @escaping @Sendable (Status) -> Void) {
        self.config = config
        self.onStatus = onStatus
    }

    /// Starts downloading and loading the model in the background, so the first dictation is fast.
    func prepare() {
        _ = startLoading()
    }

    /// Transcriptions run strictly one after another. An actor alone doesn't guarantee that:
    /// while one call is suspended inside WhisperKit, another call could start on the same model.
    func transcribe(samples: [Int16]) async throws -> String {
        let previous = lastJob
        let job = Task {
            _ = try? await previous?.value
            return try await self.transcribeNow(samples: samples)
        }
        lastJob = job
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            job.cancel()
        }
    }

    private func transcribeNow(samples: [Int16]) async throws -> String {
        try Task.checkCancellation()
        if kit == nil {
            do {
                try await startLoading().value
            } catch {
                loading = nil // let the next dictation retry
                throw OnDeviceError.modelLoad(error.localizedDescription)
            }
        }
        guard let kit else { throw OnDeviceError.modelLoad("the model didn't finish loading") }

        var options = DecodingOptions(
            language: config.language,
            detectLanguage: config.language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        if !config.dictionary.isEmpty, let tokenizer = kit.tokenizer {
            // A prompt of dictionary words nudges Whisper toward those spellings.
            let limit = tokenizer.specialTokens.specialTokenBegin
            options.promptTokens = tokenizer
                .encode(text: " " + config.dictionary.joined(separator: ", "))
                .filter { $0 < limit }
        }
        let audio = AudioFormat.paddedForWhisper(AudioFormat.floatSamples(samples), clipSeconds: options.windowClipTime)
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startLoading() -> Task<Void, Error> {
        if let loading { return loading }
        let task = Task { try await self.load() }
        loading = task
        return task
    }

    private func load() async throws {
        onStatus(.loading)
        do {
            let folder = config.whisperModelFolder
                .flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath }
            try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
            kit = try await WhisperKit(WhisperKitConfig(
                model: folder == nil ? config.whisperModel : nil,
                downloadBase: Self.modelsDirectory,
                modelRepo: config.whisperModelRepo.flatMap { $0.isEmpty ? nil : $0 },
                modelFolder: folder,
                verbose: false,
                prewarm: true,
                load: true,
                download: folder == nil
            ))
            onStatus(.ready)
        } catch {
            onStatus(.failed(OnDeviceError.modelLoad(error.localizedDescription).localizedDescription))
            throw error
        }
    }
}

enum OnDeviceError: LocalizedError {
    case modelLoad(String)

    var errorDescription: String? {
        switch self {
        case let .modelLoad(reason):
            return "Couldn't load the on-device speech model: \(reason). The first run needs internet to download it; check whisperModel in ~/.config/flowlite/config.json."
        }
    }
}
