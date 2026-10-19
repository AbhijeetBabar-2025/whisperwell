import Foundation

/// Rewrites a raw transcript with Claude via the Messages API (raw HTTP; Swift has no official SDK).
public struct Cleaner: Sendable {
    public static let serviceName = "Claude cleanup"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Models that accept server-side refusal fallbacks with `fallbacks: "default"`.
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1"]
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: String
    let model: String
    let effort: String
    let transport: HTTPTransport

    public init(config: Config, transport: HTTPTransport = URLSessionTransport()) throws {
        guard let key = config.anthropicAPIKey, !key.isEmpty else {
            throw APIError.missingAPIKey(
                service: Self.serviceName,
                hint: "Set anthropicAPIKey in ~/.config/whisperwell/config.json or export ANTHROPIC_API_KEY. Set cleanupEnabled to false to paste raw transcripts."
            )
        }
        apiKey = key
        model = config.cleanupModel
        effort = config.cleanupEffort
        self.transport = transport
    }

    public func makeRequest(transcript: String, context: TextContext?, dictionary: [String]) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": CleanupPrompt.system,
            "messages": [[
                "role": "user",
                "content": CleanupPrompt.userMessage(transcript: transcript, context: context, dictionary: dictionary),
            ]],
        ]
        if !effort.isEmpty {
            body["output_config"] = ["effort": effort]
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if Self.fallbackModels.contains(model) {
            // If a safety classifier declines, the API re-runs the request on a recommended model.
            body["fallbacks"] = "default"
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func clean(transcript: String, context: TextContext?, dictionary: [String] = []) async throws -> String {
        let request = try makeRequest(transcript: transcript, context: context, dictionary: dictionary)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(service: Self.serviceName, status: response.statusCode,
                                body: String(decoding: data, as: UTF8.self))
        }

        struct Block: Decodable { let type: String; let text: String? }
        struct StopDetails: Decodable { let category: String? }
        struct Message: Decodable {
            let content: [Block]
            let stop_reason: String?
            let stop_details: StopDetails?
        }
        let message: Message
        do {
            message = try JSONDecoder().decode(Message.self, from: data)
        } catch {
            throw APIError.invalidResponse(service: Self.serviceName, detail: "could not decode message: \(error)")
        }

        // Check the stop reason before trusting the content.
        switch message.stop_reason {
        case "refusal": throw APIError.refused(category: message.stop_details?.category)
        case "max_tokens": throw APIError.truncated
        default: break
        }
        return message.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
