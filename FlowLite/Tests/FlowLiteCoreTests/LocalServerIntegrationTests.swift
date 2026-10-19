import XCTest
@testable import FlowLiteCore

/// Uses the real URLSession transport, so these exercise the actual network stack.
final class LocalServerIntegrationTests: XCTestCase {
    func testNothingListeningGivesStartServerHint() async {
        var config = Config()
        config.localLLMBaseURL = "http://127.0.0.1:1/v1" // port 1 is never open
        do {
            _ = try await LocalCleaner(config: config).clean(transcript: "hi", context: nil)
            XCTFail("expected an error")
        } catch {
            guard case APIError.unreachable = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    /// Runs only when pointed at a live server, e.g.
    /// FLOWLITE_LOCAL_LLM_URL=http://localhost:11434/v1 FLOWLITE_LOCAL_LLM_MODEL=llama3.2 swift test
    func testLiveLocalModel() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["FLOWLITE_LOCAL_LLM_URL"] else {
            throw XCTSkip("Set FLOWLITE_LOCAL_LLM_URL to test against a running local model server")
        }
        var config = Config()
        config.localLLMBaseURL = url
        config.localLLMModel = env["FLOWLITE_LOCAL_LLM_MODEL"] ?? config.localLLMModel
        let text = try await LocalCleaner(config: config)
            .clean(transcript: "um so lets meet at 5 actually 6pm tomorrow", context: TextContext(appName: "Messages"))
        XCTAssertFalse(text.isEmpty)
        print("Local model returned: \(text)")
    }
}
