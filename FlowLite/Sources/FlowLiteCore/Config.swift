import Foundation

public enum HotkeyChoice: String, Codable, Sendable {
    case rightOption, rightCommand, fn
}

public enum SpeechProvider: String, Codable, Sendable {
    /// Whisper running on this Mac through WhisperKit. Free, offline, no key.
    case whisperkit
    /// An OpenAI-compatible transcription API (OpenAI, Groq, or a Whisper server).
    case api
}

public enum CleanupProvider: String, Codable, Sendable {
    /// Claude through the Anthropic API.
    case anthropic
    /// A model on your own machine behind an OpenAI-compatible server (Ollama, LM Studio, llama.cpp).
    case local
}

/// User settings, read from ~/.config/flowlite/config.json.
/// Environment variables override the file (useful when running from a terminal).
public struct Config: Equatable, Sendable {
    public var asrProvider: SpeechProvider = .whisperkit
    /// WhisperKit model name from huggingface.co/argmaxinc/whisperkit-coreml, downloaded on first use.
    public var whisperModel = "large-v3-v20240930_626MB"
    /// Hugging Face repo with your own Core ML Whisper models (for example a fine-tuned one).
    public var whisperModelRepo: String?
    /// A model folder already on disk. Skips downloading.
    public var whisperModelFolder: String?

    /// `api` only: any OpenAI-compatible `/audio/transcriptions` endpoint (OpenAI, Groq, a local server).
    public var asrBaseURL = "https://api.openai.com/v1"
    public var asrModel = "gpt-4o-mini-transcribe"
    /// Not needed when `asrBaseURL` points at this machine.
    public var asrAPIKey: String?
    /// ISO-639-1 code such as "en". Leave nil to auto-detect.
    public var language: String?

    public var cleanupEnabled = true
    public var cleanupProvider: CleanupProvider = .anthropic
    public var anthropicAPIKey: String?
    public var cleanupModel = "claude-haiku-5-5"
    /// "low" keeps latency down for short dictations. Set to "" to omit the field.
    public var cleanupEffort = "low"

    /// Used when `cleanupProvider` is `local`. Defaults to Ollama; LM Studio is http://localhost:1234/v1.
    public var localLLMBaseURL = "http://localhost:11434/v1"
    /// Leave empty to use whichever model the server has loaded.
    public var localLLMModel = "llama3.2"
    /// Most local servers don't need one.
    public var localLLMAPIKey: String?

    public var hotkey: HotkeyChoice = .rightOption
    /// A soft sound when the mic starts listening and when it stops.
    public var playSounds = true
    /// A floating "Listening…" indicator at the bottom of the screen.
    public var showIndicator = true
    /// Show the words in the indicator as you speak (on-device speech only).
    public var livePreview = true
    /// Paste transcripts of this many words or fewer without cleanup, for speed. 0 always cleans up.
    public var skipCleanupMaxWords = 4
    /// Names and jargon to spell correctly. Sent to both speech-to-text and cleanup.
    public var dictionary: [String] = []

    public init() {}

    /// One line for the menu: what turns speech into text.
    public var speechSummary: String {
        switch asrProvider {
        case .whisperkit:
            if let folder = whisperModelFolder, !folder.isEmpty {
                return "Speech: on-device \((folder as NSString).lastPathComponent)"
            }
            return "Speech: on-device \(whisperModel)"
        case .api:
            return "Speech: \(asrModel) at \(asrBaseURL)"
        }
    }

    /// One line for the menu: which model cleans up dictations.
    public var cleanupSummary: String {
        guard cleanupEnabled else { return "Cleanup: off (pastes raw transcript)" }
        switch cleanupProvider {
        case .anthropic: return "Cleanup: Claude \(cleanupModel)"
        case .local:
            let model = localLLMModel.isEmpty ? "loaded model" : localLLMModel
            return "Cleanup: local \(model) at \(localLLMBaseURL)"
        }
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/flowlite/config.json")
    }

    /// Writes the settings file, readable only by this user since it can hold API keys.
    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func load(
        from url: URL = defaultURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Config {
        var config = Config()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
            } catch {
                throw ConfigError.invalidFile(path: url.path, reason: String(describing: error))
            }
        }
        if let key = environment["FLOWLITE_ASR_API_KEY"] ?? environment["OPENAI_API_KEY"], !key.isEmpty {
            config.asrAPIKey = key
        }
        if let key = environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            config.anthropicAPIKey = key
        }
        return config
    }
}

extension Config: Codable {
    enum CodingKeys: String, CodingKey {
        case asrProvider, whisperModel, whisperModelRepo, whisperModelFolder
        case asrBaseURL, asrModel, asrAPIKey, language
        case cleanupEnabled, cleanupProvider, anthropicAPIKey, cleanupModel, cleanupEffort
        case localLLMBaseURL, localLLMModel, localLLMAPIKey
        case hotkey, playSounds, showIndicator, livePreview, skipCleanupMaxWords, dictionary
    }

    // Every field is optional in the file; missing ones keep their defaults.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asrProvider = try c.decodeIfPresent(SpeechProvider.self, forKey: .asrProvider) ?? asrProvider
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? whisperModel
        whisperModelRepo = try c.decodeIfPresent(String.self, forKey: .whisperModelRepo)
        whisperModelFolder = try c.decodeIfPresent(String.self, forKey: .whisperModelFolder)
        asrBaseURL = try c.decodeIfPresent(String.self, forKey: .asrBaseURL) ?? asrBaseURL
        asrModel = try c.decodeIfPresent(String.self, forKey: .asrModel) ?? asrModel
        asrAPIKey = try c.decodeIfPresent(String.self, forKey: .asrAPIKey)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? cleanupEnabled
        cleanupProvider = try c.decodeIfPresent(CleanupProvider.self, forKey: .cleanupProvider) ?? cleanupProvider
        anthropicAPIKey = try c.decodeIfPresent(String.self, forKey: .anthropicAPIKey)
        cleanupModel = try c.decodeIfPresent(String.self, forKey: .cleanupModel) ?? cleanupModel
        cleanupEffort = try c.decodeIfPresent(String.self, forKey: .cleanupEffort) ?? cleanupEffort
        localLLMBaseURL = try c.decodeIfPresent(String.self, forKey: .localLLMBaseURL) ?? localLLMBaseURL
        localLLMModel = try c.decodeIfPresent(String.self, forKey: .localLLMModel) ?? localLLMModel
        localLLMAPIKey = try c.decodeIfPresent(String.self, forKey: .localLLMAPIKey)
        hotkey = try c.decodeIfPresent(HotkeyChoice.self, forKey: .hotkey) ?? hotkey
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? playSounds
        showIndicator = try c.decodeIfPresent(Bool.self, forKey: .showIndicator) ?? showIndicator
        livePreview = try c.decodeIfPresent(Bool.self, forKey: .livePreview) ?? livePreview
        skipCleanupMaxWords = try c.decodeIfPresent(Int.self, forKey: .skipCleanupMaxWords) ?? skipCleanupMaxWords
        dictionary = try c.decodeIfPresent([String].self, forKey: .dictionary) ?? dictionary
    }
}

public enum ConfigError: LocalizedError, Equatable {
    case invalidFile(path: String, reason: String)
    case invalidValue(field: String, value: String)
    case onDeviceSpeechUnavailable

    public var errorDescription: String? {
        switch self {
        case let .invalidFile(path, reason):
            return "Couldn't read config at \(path): \(reason). Fix the JSON or delete the file to start from defaults."
        case let .invalidValue(field, value):
            return "Config field \(field) has an invalid value \"\(value)\". Check ~/.config/flowlite/config.json."
        case .onDeviceSpeechUnavailable:
            return "On-device speech isn't available in this build. Set \"asrProvider\": \"api\" in ~/.config/flowlite/config.json."
        }
    }
}
