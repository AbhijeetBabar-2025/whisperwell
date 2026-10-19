import XCTest
@testable import WhisperwellCore

final class TranscriberTests: XCTestCase {
    private func config(key: String? = "sk-test") -> Config {
        var config = Config()
        config.asrAPIKey = key
        config.asrBaseURL = "https://api.groq.com/openai/v1"
        config.asrModel = "whisper-large-v3-turbo"
        config.language = "en"
        return config
    }

    func testSendsMultipartRequestAndParsesText() async throws {
        let transport = MockTransport(json: #"{"text": "  hello world \n"}"#)
        let text = try await Transcriber(config: config(), transport: transport)
            .transcribe(wav: Data("RIFF".utf8), vocabulary: ["Wispr", "Baseten"])

        XCTAssertEqual(text, "hello world")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen"))
        XCTAssertTrue(body.contains("Vocabulary: Wispr, Baseten"))
        XCTAssertTrue(body.contains("filename=\"audio.wav\""))
    }

    func testHTTPErrorIncludesStatusAndBody() async throws {
        let transport = MockTransport(status: 401, json: #"{"error": "bad key"}"#)
        do {
            _ = try await Transcriber(config: config(), transport: transport).transcribe(wav: Data())
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(service: "Speech-to-text", status: 401, body: #"{"error": "bad key"}"#))
            XCTAssertTrue(error.localizedDescription.contains("Check the API key"))
        }
    }

    func testMissingKeyThrows() {
        XCTAssertThrowsError(try Transcriber(config: config(key: nil), transport: MockTransport(json: "{}"))) { error in
            guard case APIError.missingAPIKey = error else { return XCTFail("wrong error: \(error)") }
        }
    }
}

final class CleanerTests: XCTestCase {
    private func config(model: String = "claude-opus-5-5", effort: String = "low") -> Config {
        var config = Config()
        config.anthropicAPIKey = "ant-test"
        config.cleanupModel = model
        config.cleanupEffort = effort
        return config
    }

    private let okJSON = #"""
    {"content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "Let's meet at 6pm."}],
     "stop_reason": "end_turn", "stop_details": null}
    """#

    func testBuildsMessagesRequestWithFallbacks() async throws {
        let transport = MockTransport(json: okJSON)
        var context = TextContext(appName: "Mail")
        context.textBefore = "Hi Sam,\n"
        let text = try await Cleaner(config: config(), transport: transport)
            .clean(transcript: "lets meet at 5 actually 6pm", context: context)

        XCTAssertEqual(text, "Let's meet at 6pm.")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")

        let body = try jsonBody(request)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "low")
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["temperature"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0]["content"]?.contains("<app>\nMail\n</app>") ?? false)
        XCTAssertTrue(messages[0]["content"]?.contains("lets meet at 5 actually 6pm") ?? false)
    }

    func testDefaultConfigUsesHaikuWithLowEffortAndNoFallbacks() throws {
        var defaults = Config()
        defaults.anthropicAPIKey = "ant-test"
        let request = try Cleaner(config: defaults, transport: MockTransport(json: "{}"))
            .makeRequest(transcript: "hi", context: nil, dictionary: [])
        let body = try jsonBody(request)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "low")
        XCTAssertNil(body["fallbacks"])
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testOmitsFallbacksForModelsWithoutThem() throws {
        let request = try Cleaner(config: config(model: "claude-haiku-5-5", effort: ""), transport: MockTransport(json: "{}"))
            .makeRequest(transcript: "hi", context: nil, dictionary: [])
        let body = try jsonBody(request)
        XCTAssertNil(body["fallbacks"])
        XCTAssertNil(body["output_config"])
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testRefusalThrowsWithCategory() async {
        let transport = MockTransport(json: #"{"content": [], "stop_reason": "refusal", "stop_details": {"type": "refusal", "category": "cyber"}}"#)
        do {
            _ = try await Cleaner(config: config(), transport: transport).clean(transcript: "x", context: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .refused(category: "cyber"))
        }
    }

    func testMaxTokensThrowsTruncated() async {
        let transport = MockTransport(json: #"{"content": [{"type": "text", "text": "partial"}], "stop_reason": "max_tokens"}"#)
        do {
            _ = try await Cleaner(config: config(), transport: transport).clean(transcript: "x", context: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .truncated)
        }
    }
}

final class DictationPipelineTests: XCTestCase {
    struct Boom: Error {}

    func testCleanupFailureFallsBackToRawTranscript() async throws {
        let logged = LockedArray()
        let pipeline = DictationPipeline(
            transcribe: { _ in "raw text" },
            clean: { _ in throw Boom() },
            log: { logged.append($0) }
        )
        let result = try await pipeline.run(samples: [1, 2, 3])
        XCTAssertEqual(result, "raw text")
        XCTAssertEqual(logged.values.count, 1)
    }

    func testDetailedResultKeepsRawAndCleaned() async throws {
        let pipeline = DictationPipeline(transcribe: { _ in "um hi there" }, clean: { _ in "Hi there." })
        let result = try await pipeline.runDetailed(samples: [1])
        XCTAssertEqual(result, DictationPipeline.Result(raw: "um hi there", text: "Hi there."))
    }

    func testEmptyTranscriptSkipsCleanup() async throws {
        let pipeline = DictationPipeline(
            transcribe: { _ in "" },
            clean: { _ in XCTFail("cleanup should not run"); return "x" }
        )
        let result = try await pipeline.run(samples: [1, 2, 3])
        XCTAssertEqual(result, "")
    }

    func testTranscriptionErrorPropagates() async {
        let pipeline = DictationPipeline(transcribe: { _ in throw Boom() }, clean: nil)
        do {
            _ = try await pipeline.run(samples: [1, 2, 3])
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    func testMakeWithoutAnthropicKeyRunsWithoutCleanup() async throws {
        var config = Config()
        config.asrProvider = .api
        config.asrAPIKey = "sk-test"
        let logged = LockedArray()
        let transport = MockTransport(json: #"{"text": "plain"}"#)
        let pipeline = try DictationPipeline.make(config: config, context: TextContext(), transport: transport) {
            logged.append($0)
        }
        let result = try await pipeline.run(samples: [1, 2, 3])
        XCTAssertEqual(result, "plain")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(logged.values.first?.contains("Cleanup is off") ?? false)
    }
}

final class LockedArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
