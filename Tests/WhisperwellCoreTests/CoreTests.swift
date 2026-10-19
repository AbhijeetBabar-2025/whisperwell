import XCTest
@testable import WhisperwellCore

final class WAVEncoderTests: XCTestCase {
    func testHeaderAndSamples() {
        let data = WAVEncoder.encode(samples: [0, 1, -1], sampleRate: 16_000)
        XCTAssertEqual(data.count, 44 + 6)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")

        func u32(_ offset: Int) -> UInt32 { data[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        XCTAssertEqual(u32(4), 36 + 6)       // RIFF size
        XCTAssertEqual(u32(24), 16_000)      // sample rate
        XCTAssertEqual(u32(28), 32_000)      // byte rate
        XCTAssertEqual(u32(40), 6)           // data size
        XCTAssertEqual(Array(data[44...]), [0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF])
    }
}

final class MultipartFormTests: XCTestCase {
    func testFieldsFileAndClosingBoundary() {
        var form = MultipartForm(boundary: "B")
        form.addField(name: "model", value: "m1")
        form.addFile(name: "file", filename: "a.wav", contentType: "audio/wav", data: Data("XYZ".utf8))
        let body = String(decoding: form.finalized(), as: UTF8.self)

        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=B")
        XCTAssertTrue(body.contains("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nm1\r\n"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\nXYZ\r\n"))
        XCTAssertTrue(body.hasSuffix("--B--\r\n"))
    }
}

final class TextContextTests: XCTestCase {
    func testSplitsAroundSelection() {
        var context = TextContext()
        context.setFieldValue("Hello brave world", selectionLocation: 6, selectionLength: 5)
        XCTAssertEqual(context.textBefore, "Hello ")
        XCTAssertEqual(context.selectedText, "brave")
        XCTAssertEqual(context.textAfter, " world")
    }

    func testClampsOutOfRangeSelection() {
        var context = TextContext()
        context.setFieldValue("abc", selectionLocation: 10, selectionLength: 5)
        XCTAssertEqual(context.textBefore, "abc")
        XCTAssertEqual(context.selectedText, "")
        XCTAssertEqual(context.textAfter, "")
    }

    func testUsesUTF16Offsets() {
        // "👋" is 2 UTF-16 units; Accessibility reports the cursor after it as 2.
        var context = TextContext()
        context.setFieldValue("👋hi", selectionLocation: 2, selectionLength: 0)
        XCTAssertEqual(context.textBefore, "👋")
        XCTAssertEqual(context.textAfter, "hi")
    }
}

final class CleanupPromptTests: XCTestCase {
    func testIncludesContextAndKeepsTextNearestCursor() {
        var context = TextContext(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        context.textBefore = String(repeating: "a", count: 600) + "END"
        context.textAfter = "START" + String(repeating: "b", count: 600)
        let message = CleanupPrompt.userMessage(transcript: "um hi there", context: context, dictionary: ["Wispr"])

        XCTAssertTrue(message.contains("<app>\nSlack (com.tinyspeck.slackmacgap)\n</app>"))
        XCTAssertTrue(message.contains("END\n</text_before_cursor>"))
        XCTAssertTrue(message.contains("<text_after_cursor>\nSTART"))
        XCTAssertFalse(message.contains(String(repeating: "a", count: 501)))
        XCTAssertTrue(message.contains("<dictionary>\nWispr\n</dictionary>"))
        XCTAssertTrue(message.hasSuffix("<transcript>\num hi there\n</transcript>"))
    }

    func testRemovesEchoedTextBeforeCursor() {
        let before = "Shopping list\nRemember to call the dentist tomorrow morning.\n"
        let echoed = "Remember to call the dentist tomorrow morning. Also, pick up some milk."
        XCTAssertEqual(CleanupPrompt.removingEchoedContext(echoed, textBefore: before), "Also, pick up some milk.")
    }

    func testKeepsOutputThatDoesNotEcho() {
        let before = "Remember to call the dentist tomorrow morning."
        XCTAssertEqual(CleanupPrompt.removingEchoedContext("Also, pick up some milk.", textBefore: before),
                       "Also, pick up some milk.")
        // Fewer than 4 matching words is treated as coincidence, not an echo.
        XCTAssertEqual(CleanupPrompt.removingEchoedContext("tomorrow morning. Then lunch.", textBefore: before),
                       "tomorrow morning. Then lunch.")
        // Never strip everything, even if the whole reply matches.
        XCTAssertEqual(CleanupPrompt.removingEchoedContext("call the dentist tomorrow morning.", textBefore: before),
                       "call the dentist tomorrow morning.")
        XCTAssertEqual(CleanupPrompt.removingEchoedContext("Hello there.", textBefore: ""), "Hello there.")
    }

    func testOmitsEmptySections() {
        let message = CleanupPrompt.userMessage(transcript: "hi", context: TextContext(), dictionary: [])
        XCTAssertEqual(message, "<transcript>\nhi\n</transcript>")
    }
}

final class ConfigTests: XCTestCase {
    private let secrets = InMemorySecretStore()

    private func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("whisperwell-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMissingFieldsKeepDefaults() throws {
        let config = try Config.load(from: write(#"{"hotkey": "fn", "dictionary": ["Kubernetes"]}"#), environment: [:], secrets: secrets)
        XCTAssertEqual(config.hotkey, .fn)
        XCTAssertEqual(config.dictionary, ["Kubernetes"])
        XCTAssertEqual(config.asrModel, Config().asrModel)
        XCTAssertEqual(config.cleanupModel, "claude-haiku-5-5")
        XCTAssertTrue(config.cleanupEnabled)
    }

    func testEnvironmentOverridesFileKeys() throws {
        let url = try write(#"{"asrAPIKey": "file-key", "anthropicAPIKey": "file-ant"}"#)
        let config = try Config.load(from: url, environment: ["OPENAI_API_KEY": "env-key", "ANTHROPIC_API_KEY": "env-ant"], secrets: secrets)
        XCTAssertEqual(config.asrAPIKey, "env-key")
        XCTAssertEqual(config.anthropicAPIKey, "env-ant")
    }

    func testMissingFileUsesDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        XCTAssertEqual(try Config.load(from: url, environment: [:], secrets: secrets), Config())
    }

    func testSaveRoundTripsAndIsPrivate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperwell-\(UUID().uuidString)/config.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var config = Config()
        config.hotkey = .fn
        config.cleanupProvider = .local
        config.localLLMBaseURL = "http://10.0.0.82:1234/v1"
        config.anthropicAPIKey = "secret"
        config.dictionary = ["Kubernetes"]
        try config.save(to: url, secrets: secrets)

        XCTAssertEqual(try Config.load(from: url, environment: [:], secrets: secrets), config)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertTrue(try String(contentsOf: url).contains("http://10.0.0.82:1234/v1"), "URLs stay readable")
    }

    func testInvalidJSONExplainsWhere() throws {
        let url = try write("{not json")
        XCTAssertThrowsError(try Config.load(from: url, environment: [:], secrets: secrets)) { error in
            XCTAssertTrue(error.localizedDescription.contains(url.path))
        }
    }

    func testSaveKeepsKeysOutOfTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperwell-\(UUID().uuidString)/config.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var config = Config()
        config.anthropicAPIKey = "sk-ant-secret"
        config.asrAPIKey = "sk-asr-secret"
        config.localLLMAPIKey = "lm-secret"
        try config.save(to: url, secrets: secrets)

        let text = try String(contentsOf: url)
        XCTAssertFalse(text.contains("secret"), "keys must not be written to the file")
        XCTAssertEqual(try secrets.get("anthropicAPIKey"), "sk-ant-secret")
        XCTAssertEqual(try secrets.get("asrAPIKey"), "sk-asr-secret")
        XCTAssertEqual(try secrets.get("localLLMAPIKey"), "lm-secret")
        XCTAssertEqual(try Config.load(from: url, environment: [:], secrets: secrets), config)

        config.anthropicAPIKey = ""
        try config.save(to: url, secrets: secrets)
        XCTAssertNil(try secrets.get("anthropicAPIKey"), "clearing a key in Settings deletes it")
    }

    func testKeySourcesInOrder() throws {
        try secrets.set("anthropicAPIKey", "keychain-ant")
        try secrets.set("asrAPIKey", "keychain-asr")
        try secrets.set("localLLMAPIKey", "keychain-local")
        let url = try write(#"{"asrAPIKey": "file-asr"}"#)
        let config = try Config.load(from: url, environment: ["ANTHROPIC_API_KEY": "env-ant"], secrets: secrets)
        XCTAssertEqual(config.anthropicAPIKey, "env-ant", "environment beats everything")
        XCTAssertEqual(config.asrAPIKey, "file-asr", "a key typed into the file beats the Keychain")
        XCTAssertEqual(config.localLLMAPIKey, "keychain-local")
    }

    func testMovesFileKeysToKeychain() throws {
        let url = try write(#"{"hotkey": "fn", "anthropicAPIKey": "sk-ant-old", "localLLMAPIKey": ""}"#)
        XCTAssertTrue(try Config.moveKeysToKeychain(at: url, secrets: secrets))

        XCTAssertEqual(try secrets.get("anthropicAPIKey"), "sk-ant-old")
        let text = try String(contentsOf: url)
        XCTAssertFalse(text.contains("APIKey"), text)
        XCTAssertTrue(text.contains("\"fn\""), "other settings are kept")
        XCTAssertFalse(try Config.moveKeysToKeychain(at: url, secrets: secrets), "second run has nothing to do")
    }

    func testMoveKeysWithoutFileDoesNothing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        XCTAssertFalse(try Config.moveKeysToKeychain(at: url, secrets: secrets))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
