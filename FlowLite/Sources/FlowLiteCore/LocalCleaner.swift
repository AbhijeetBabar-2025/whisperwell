import Foundation

/// Cleans up a transcript with a model running on this machine, through the
/// OpenAI-compatible `POST {base}/chat/completions` endpoint that Ollama,
/// LM Studio and llama.cpp's server all provide.
public struct LocalCleaner: Sendable {
    public static let serviceName = "Local model cleanup"

    let baseURL: URL
    let model: String
    let apiKey: String?
    let transport: HTTPTransport

    public init(config: Config, transport: HTTPTransport = URLSessionTransport()) throws {
        guard let url = URL(string: config.localLLMBaseURL), url.scheme != nil else {
            throw ConfigError.invalidValue(field: "localLLMBaseURL", value: config.localLLMBaseURL)
        }
        baseURL = url
        model = config.localLLMModel
        apiKey = config.localLLMAPIKey.flatMap { $0.isEmpty ? nil : $0 }
        self.transport = transport
    }

    public func makeRequest(transcript: String, context: TextContext?, dictionary: [String], model: String? = nil) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model ?? self.model,
            "stream": false,
            // Low temperature keeps small models from rewording what was said.
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": CleanupPrompt.system],
                ["role": "user", "content": CleanupPrompt.userMessage(transcript: transcript, context: context, dictionary: dictionary)],
            ],
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        // The first request after a model loads can take a while on a laptop.
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func clean(transcript: String, context: TextContext?, dictionary: [String] = []) async throws -> String {
        let model = self.model.isEmpty ? try await loadedModel() : self.model
        let request = try makeRequest(transcript: transcript, context: context, dictionary: dictionary, model: model)
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            if response.statusCode == 404, body.localizedCaseInsensitiveContains("model") {
                throw APIError.http(service: Self.serviceName, status: 404,
                                    body: "Model \"\(model)\" isn't installed. For Ollama run `ollama pull \(model)`. Server said: \(body)")
            }
            throw APIError.http(service: Self.serviceName, status: response.statusCode, body: body)
        }

        struct Message: Decodable { let content: String? }
        struct Choice: Decodable { let message: Message; let finish_reason: String? }
        struct Completion: Decodable { let choices: [Choice] }
        let completion: Completion
        do {
            completion = try JSONDecoder().decode(Completion.self, from: data)
        } catch {
            throw APIError.invalidResponse(service: Self.serviceName, detail: "could not decode chat completion: \(error)")
        }
        guard let choice = completion.choices.first else {
            throw APIError.invalidResponse(service: Self.serviceName, detail: "no choices in response")
        }
        if choice.finish_reason == "length" { throw APIError.truncated }
        return Self.stripReasoning(choice.message.content ?? "")
    }

    /// Checks the server answers and has the configured model. Returns the model that will be used.
    public func checkServer() async throws -> String {
        if model.isEmpty { return try await loadedModel() }
        let available = try await listModels()
        guard available.contains(model) else {
            throw APIError.invalidResponse(
                service: Self.serviceName,
                detail: "model \"\(model)\" isn't loaded. Available: \(available.joined(separator: ", ")). Load it or fix localLLMModel."
            )
        }
        return model
    }

    /// With `localLLMModel` empty, use the first chat model the server lists (LM Studio lists the loaded ones).
    func loadedModel() async throws -> String {
        let ids = try await listModels()
        // Embedding models can't write text, so skip them.
        guard let first = ids.first(where: { !$0.localizedCaseInsensitiveContains("embed") }) else {
            throw APIError.invalidResponse(
                service: Self.serviceName,
                detail: "no models are loaded at \(baseURL.absoluteString). Load one in your model server, or set localLLMModel."
            )
        }
        return first
    }

    func listModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 10
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(service: Self.serviceName, status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        struct Model: Decodable { let id: String }
        struct List: Decodable { let data: [Model] }
        return (try? JSONDecoder().decode(List.self, from: data))?.data.map(\.id) ?? []
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .cannotFindHost {
            let pull = model.isEmpty ? "" : ", then `ollama pull \(model)`"
            throw APIError.unreachable(
                service: Self.serviceName,
                url: baseURL.absoluteString,
                hint: "Start your local model server (LM Studio: Developer tab › Start Server; Ollama: `ollama serve`\(pull))."
            )
        } catch let error as URLError where error.code == .notConnectedToInternet && !baseURL.isLocalHost {
            // macOS reports a blocked Local Network permission as "offline".
            throw APIError.unreachable(
                service: Self.serviceName,
                url: baseURL.absoluteString,
                hint: "macOS may be blocking it: allow FlowLite under System Settings › Privacy & Security › Local Network, then relaunch FlowLite."
            )
        }
    }

    /// Reasoning models (Qwen 3, DeepSeek-R1) put their thinking in <think> tags; drop it.
    static func stripReasoning(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<think>"),
              let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
