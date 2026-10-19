import XCTest
@testable import FlowLiteCore

/// Throws a fixed URLError, like URLSession does when nothing is listening on the port.
struct FailingTransport: HTTPTransport {
    let code: URLError.Code
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(code)
    }
}

final class LocalCleanerTests: XCTestCase {
    private func config(key: String? = nil) -> Config {
        var config = Config()
        config.cleanupProvider = .local
        config.localLLMBaseURL = "http://localhost:11434/v1"
        config.localLLMModel = "llama3.2"
        config.localLLMAPIKey = key
        return config
    }

    private let okJSON = #"{"choices": [{"message": {"role": "assistant", "content": "Let's meet at 6pm."}, "finish_reason": "stop"}]}"#

    func testSendsChatCompletionWithCleanupPrompt() async throws {
        let transport = MockTransport(json: okJSON)
        let text = try await LocalCleaner(config: config(), transport: transport)
            .clean(transcript: "lets meet at 5 actually 6pm", context: TextContext(appName: "Mail"), dictionary: ["Sam"])

        XCTAssertEqual(text, "Let's meet at 6pm.")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try jsonBody(request)
        XCTAssertEqual(body["model"] as? String, "llama3.2")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages[0]["content"], CleanupPrompt.system)
        XCTAssertTrue(messages[1]["content"]?.contains("<app>\nMail\n</app>") ?? false)
        XCTAssertTrue(messages[1]["content"]?.contains("<dictionary>\nSam\n</dictionary>") ?? false)
    }

    func testSendsAPIKeyWhenConfigured() throws {
        let request = try LocalCleaner(config: config(key: "lm-key"), transport: MockTransport(json: "{}"))
            .makeRequest(transcript: "hi", context: nil, dictionary: [])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer lm-key")
    }

    func testStripsReasoningTags() async throws {
        let json = #"{"choices": [{"message": {"content": "<think>\nThe user said hi.\n</think>\n\nHi there."}, "finish_reason": "stop"}]}"#
        let text = try await LocalCleaner(config: config(), transport: MockTransport(json: json))
            .clean(transcript: "hi there", context: nil)
        XCTAssertEqual(text, "Hi there.")
    }

    func testLengthFinishThrowsTruncated() async {
        let json = #"{"choices": [{"message": {"content": "partial"}, "finish_reason": "length"}]}"#
        do {
            _ = try await LocalCleaner(config: config(), transport: MockTransport(json: json)).clean(transcript: "x", context: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .truncated)
        }
    }

    func testServerNotRunningExplainsHowToStartIt() async {
        do {
            _ = try await LocalCleaner(config: config(), transport: FailingTransport(code: .cannotConnectToHost))
                .clean(transcript: "x", context: nil)
            XCTFail("expected an error")
        } catch {
            guard case APIError.unreachable = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertTrue(error.localizedDescription.contains("ollama pull llama3.2"))
        }
    }

    func testBlockedLocalNetworkPointsToPrivacySetting() async {
        var lan = config()
        lan.localLLMBaseURL = "http://10.0.0.82:1234/v1"
        do {
            _ = try await LocalCleaner(config: lan, transport: FailingTransport(code: .notConnectedToInternet))
                .clean(transcript: "x", context: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Local Network"))
        }
    }

    func testMissingModelExplainsHowToPullIt() async {
        let transport = MockTransport(status: 404, json: #"{"error": {"message": "model \"llama3.2\" not found, try pulling it first"}}"#)
        do {
            _ = try await LocalCleaner(config: config(), transport: transport).clean(transcript: "x", context: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("isn't installed"))
        }
    }

    func testEmptyModelNameUsesTheLoadedModel() async throws {
        var auto = config()
        auto.localLLMBaseURL = "http://localhost:1234/v1"
        auto.localLLMModel = ""
        // One canned body answers both calls: "data" for /models, "choices" for the chat call.
        let transport = MockTransport(json: #"{"data": [{"id": "text-embedding-nomic-embed-text-v1.5"}, {"id": "qwen2.5-7b-instruct"}], "choices": [{"message": {"content": "Hi."}, "finish_reason": "stop"}]}"#)
        let text = try await LocalCleaner(config: auto, transport: transport).clean(transcript: "hi", context: nil)

        XCTAssertEqual(text, "Hi.")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString },
                       ["http://localhost:1234/v1/models", "http://localhost:1234/v1/chat/completions"])
        XCTAssertEqual(try jsonBody(transport.requests[1])["model"] as? String, "qwen2.5-7b-instruct")
        XCTAssertEqual(auto.cleanupSummary, "Cleanup: local loaded model at http://localhost:1234/v1")
    }

    func testCheckServerConfirmsPinnedModel() async throws {
        let transport = MockTransport(json: #"{"data": [{"id": "qwen2.5-14b-instruct"}, {"id": "llama3.2"}]}"#)
        let model = try await LocalCleaner(config: config(), transport: transport).checkServer()
        XCTAssertEqual(model, "llama3.2")
    }

    func testCheckServerReportsMissingPinnedModel() async {
        let transport = MockTransport(json: #"{"data": [{"id": "qwen2.5-14b-instruct"}]}"#)
        do {
            _ = try await LocalCleaner(config: config(), transport: transport).checkServer()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Available: qwen2.5-14b-instruct"))
        }
    }

    func testEmptyModelNameWithNothingLoadedExplains() async {
        var auto = config()
        auto.localLLMModel = ""
        do {
            _ = try await LocalCleaner(config: auto, transport: MockTransport(json: #"{"data": []}"#)).clean(transcript: "hi", context: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no models are loaded"))
        }
    }
}

final class LocalAIConfigTests: XCTestCase {
    func testDecodesLocalSettings() throws {
        let json = #"{"cleanupProvider": "local", "localLLMBaseURL": "http://localhost:1234/v1", "localLLMModel": "qwen2.5-7b-instruct"}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.cleanupProvider, .local)
        XCTAssertEqual(config.localLLMBaseURL, "http://localhost:1234/v1")
        XCTAssertEqual(config.localLLMModel, "qwen2.5-7b-instruct")
        XCTAssertEqual(config.cleanupSummary, "Cleanup: local qwen2.5-7b-instruct at http://localhost:1234/v1")
    }

    func testDefaultsStayOnClaudeWithOllamaReady() {
        let config = Config()
        XCTAssertEqual(config.cleanupProvider, .anthropic)
        XCTAssertEqual(config.localLLMBaseURL, "http://localhost:11434/v1")
        XCTAssertEqual(config.localLLMModel, "llama3.2")
        XCTAssertEqual(config.cleanupSummary, "Cleanup: Claude claude-haiku-5-5")
    }

    func testSummaryWhenCleanupOff() {
        var config = Config()
        config.cleanupEnabled = false
        XCTAssertEqual(config.cleanupSummary, "Cleanup: off (pastes raw transcript)")
    }

    func testIsLocalHost() {
        XCTAssertTrue(URL(string: "http://localhost:11434/v1")!.isLocalHost)
        XCTAssertTrue(URL(string: "http://127.0.0.1:8000/v1")!.isLocalHost)
        XCTAssertFalse(URL(string: "https://api.openai.com/v1")!.isLocalHost)
    }
}

final class LocalSpeechToTextTests: XCTestCase {
    func testLocalServerNeedsNoKey() async throws {
        var config = Config()
        config.asrBaseURL = "http://127.0.0.1:8000/v1"
        config.asrModel = "Systran/faster-whisper-small"
        let transport = MockTransport(json: #"{"text": "hello"}"#)
        let text = try await Transcriber(config: config, transport: transport).transcribe(wav: Data())
        XCTAssertEqual(text, "hello")
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testLocalServerNotRunning() async {
        var config = Config()
        config.asrBaseURL = "http://localhost:8000/v1"
        do {
            _ = try await Transcriber(config: config, transport: FailingTransport(code: .cannotConnectToHost)).transcribe(wav: Data())
            XCTFail("expected an error")
        } catch {
            guard case APIError.unreachable = error else { return XCTFail("wrong error: \(error)") }
        }
    }
}

final class LocalPipelineTests: XCTestCase {
    func testLocalProviderRoutesCleanupToLocalServer() async throws {
        var config = Config()
        config.asrProvider = .api
        config.asrAPIKey = "sk-test"
        config.cleanupProvider = .local
        // Same canned body answers both calls: it has "text" for speech-to-text and "choices" for the chat call.
        let transport = MockTransport(json: #"{"text": "um hello", "choices": [{"message": {"content": "Hello."}, "finish_reason": "stop"}]}"#)
        let pipeline = try DictationPipeline.make(config: config, context: TextContext(), transport: transport)

        let result = try await pipeline.run(samples: [1, 2, 3])
        XCTAssertEqual(result, "Hello.")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString },
                       ["https://api.openai.com/v1/audio/transcriptions", "http://localhost:11434/v1/chat/completions"])
    }

    func testLocalProviderDoesNotNeedAnthropicKey() async throws {
        var config = Config()
        config.asrProvider = .api
        config.asrAPIKey = "sk-test"
        config.cleanupProvider = .local
        config.anthropicAPIKey = nil
        let logged = LockedArray()
        _ = try DictationPipeline.make(config: config, context: TextContext(), transport: MockTransport(json: "{}")) {
            logged.append($0)
        }
        XCTAssertTrue(logged.values.isEmpty, "unexpected log: \(logged.values)")
    }
}

final class OnDeviceSpeechTests: XCTestCase {
    func testDefaultsToOnDeviceWhisper() {
        let config = Config()
        XCTAssertEqual(config.asrProvider, .whisperkit)
        XCTAssertEqual(config.whisperModel, "large-v3-v20240930_626MB")
        XCTAssertEqual(config.speechSummary, "Speech: on-device large-v3-v20240930_626MB")
    }

    func testDecodesSpeechSettings() throws {
        let json = #"{"asrProvider": "whisperkit", "whisperModel": "small.en", "whisperModelRepo": "me/my-whisper", "whisperModelFolder": "~/Models/custom-whisper"}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.whisperModel, "small.en")
        XCTAssertEqual(config.whisperModelRepo, "me/my-whisper")
        XCTAssertEqual(config.speechSummary, "Speech: on-device custom-whisper")

        let api = try JSONDecoder().decode(Config.self, from: Data(#"{"asrProvider": "api"}"#.utf8))
        XCTAssertEqual(api.speechSummary, "Speech: gpt-4o-mini-transcribe at https://api.openai.com/v1")
    }

    func testOnDeviceProviderUsesInjectedTranscriberAndNeedsNoKey() async throws {
        var config = Config()
        config.cleanupEnabled = false
        let transport = MockTransport(json: "{}")
        let pipeline = try DictationPipeline.make(
            config: config, context: TextContext(), transport: transport,
            onDevice: { samples in "heard \(samples.count) samples" }
        )
        let result = try await pipeline.run(samples: [1, 2, 3])
        XCTAssertEqual(result, "heard 3 samples")
        XCTAssertTrue(transport.requests.isEmpty, "on-device speech must not call the network")
    }

    func testOnDeviceProviderWithoutTranscriberExplains() {
        XCTAssertThrowsError(try DictationPipeline.make(config: Config(), context: TextContext())) { error in
            XCTAssertEqual(error as? ConfigError, .onDeviceSpeechUnavailable)
        }
    }

    func testAPIProviderSendsWAV() async throws {
        var config = Config()
        config.asrProvider = .api
        config.asrAPIKey = "sk-test"
        config.cleanupEnabled = false
        let transport = MockTransport(json: #"{"text": "hi"}"#)
        _ = try await DictationPipeline.make(config: config, context: TextContext(), transport: transport)
            .run(samples: [0, 1])
        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        XCTAssertNotNil(body.range(of: Data("RIFF".utf8)), "upload should contain a WAV file")
    }

    func testPaddingAddsTrailingSilenceForWhisper() {
        let padded = AudioFormat.paddedForWhisper([0.5, -0.5], clipSeconds: 1.0)
        XCTAssertEqual(padded.count, 2 + 16_000)
        XCTAssertEqual(Array(padded.prefix(2)), [0.5, -0.5])
        XCTAssertTrue(padded.dropFirst(2).allSatisfy { $0 == 0 })
    }

    func testMeterLevel() {
        XCTAssertEqual(AudioFormat.meterLevel([]), 0)
        XCTAssertEqual(AudioFormat.meterLevel([0, 0, 0]), 0)
        XCTAssertEqual(AudioFormat.meterLevel([Int16.max, Int16.min]), 1, accuracy: 0.01)  // full scale
        let quiet = AudioFormat.meterLevel([Int16](repeating: 100, count: 160))           // about -50 dB
        let speech = AudioFormat.meterLevel([Int16](repeating: 3_000, count: 160))        // about -21 dB
        XCTAssertLessThan(quiet, 0.05)
        XCTAssertEqual(speech, 0.58, accuracy: 0.03)
    }

    func testFeedbackSettingsDefaultOnAndDecode() throws {
        XCTAssertTrue(Config().playSounds)
        XCTAssertTrue(Config().showIndicator)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"playSounds": false, "showIndicator": false}"#.utf8))
        XCTAssertFalse(config.playSounds)
        XCTAssertFalse(config.showIndicator)
    }

    func testLivePreviewTail() {
        XCTAssertEqual(LivePreview.tail("  short text "), "short text")
        let long = "so I was thinking we could move the launch to next Thursday because the press kit is not ready"
        let tail = LivePreview.tail(long, maxCharacters: 40)
        XCTAssertTrue(tail.hasPrefix("…"))
        XCTAssertTrue(tail.hasSuffix("press kit is not ready"))
        XCTAssertLessThanOrEqual(tail.count, 41)
        XCTAssertFalse(tail.dropFirst().hasPrefix(" "))
    }

    func testLivePreviewDefaultsOn() throws {
        XCTAssertTrue(Config().livePreview)
        XCTAssertFalse(try JSONDecoder().decode(Config.self, from: Data(#"{"livePreview": false}"#.utf8)).livePreview)
    }

    func testFloatSamplesScale() {
        XCTAssertEqual(AudioFormat.floatSamples([0, 16_384, -32_768]), [0, 0.5, -1])
    }
}

final class ShortPhraseTests: XCTestCase {
    func testSkipsCleanupOnlyForShortCleanPhrases() {
        XCTAssertTrue(ShortPhrase.canSkipCleanup("Sounds good.", maxWords: 4))
        XCTAssertTrue(ShortPhrase.canSkipCleanup("On my way home!", maxWords: 4))
        XCTAssertFalse(ShortPhrase.canSkipCleanup("Um, sounds good.", maxWords: 4))           // filler
        XCTAssertFalse(ShortPhrase.canSkipCleanup("At 5, actually 6.", maxWords: 4))          // correction
        XCTAssertFalse(ShortPhrase.canSkipCleanup("Let's meet at six tomorrow.", maxWords: 4)) // 5 words
        XCTAssertFalse(ShortPhrase.canSkipCleanup("Sounds good.", maxWords: 0))               // disabled
        XCTAssertFalse(ShortPhrase.canSkipCleanup("  ", maxWords: 4))
    }

    func testFitsPhraseToTextBeforeCursor() {
        XCTAssertEqual(ShortPhrase.fitted("Sounds good.", textBefore: ""), "Sounds good.")
        XCTAssertEqual(ShortPhrase.fitted("Sounds good.", textBefore: "Done. "), "Sounds good.")
        XCTAssertEqual(ShortPhrase.fitted("Tomorrow morning.", textBefore: "Let's meet "), "tomorrow morning.")
        XCTAssertEqual(ShortPhrase.fitted("I think so.", textBefore: "Well, "), "I think so.")
        XCTAssertEqual(ShortPhrase.fitted("PDF attached.", textBefore: "here is the "), "PDF attached.")
    }

    func testPipelineSkipsCleanupForShortPhrase() async throws {
        var config = Config()
        config.asrProvider = .api
        config.asrAPIKey = "sk-test"
        config.cleanupProvider = .local
        let transport = MockTransport(json: #"{"text": "Sounds good.", "choices": [{"message": {"content": "REWRITTEN"}, "finish_reason": "stop"}]}"#)
        let result = try await DictationPipeline.make(config: config, context: TextContext(), transport: transport)
            .run(samples: [1])
        XCTAssertEqual(result, "Sounds good.")
        XCTAssertEqual(transport.requests.count, 1, "only speech-to-text should be called")

        config.skipCleanupMaxWords = 0
        let always = MockTransport(json: #"{"text": "Sounds good.", "choices": [{"message": {"content": "REWRITTEN"}, "finish_reason": "stop"}]}"#)
        let cleaned = try await DictationPipeline.make(config: config, context: TextContext(), transport: always)
            .run(samples: [1])
        XCTAssertEqual(cleaned, "REWRITTEN")
    }
}
