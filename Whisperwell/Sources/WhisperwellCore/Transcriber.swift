import Foundation

/// Speech-to-text through any OpenAI-compatible `POST {base}/audio/transcriptions` endpoint.
public struct Transcriber: Sendable {
    public static let serviceName = "Speech-to-text"

    let baseURL: URL
    let model: String
    let apiKey: String?
    let language: String?
    let transport: HTTPTransport

    public init(config: Config, transport: HTTPTransport = URLSessionTransport()) throws {
        guard let url = URL(string: config.asrBaseURL), url.scheme != nil else {
            throw ConfigError.invalidValue(field: "asrBaseURL", value: config.asrBaseURL)
        }
        let key = config.asrAPIKey.flatMap { $0.isEmpty ? nil : $0 }
        if key == nil, !url.isLocalHost {
            throw APIError.missingAPIKey(
                service: Self.serviceName,
                hint: "Set asrAPIKey in ~/.config/whisperwell/config.json or export OPENAI_API_KEY."
            )
        }
        baseURL = url
        model = config.asrModel
        apiKey = key
        language = config.language
        self.transport = transport
    }

    public func makeRequest(wav: Data, vocabulary: [String]) -> URLRequest {
        var form = MultipartForm()
        form.addField(name: "model", value: model)
        if let language, !language.isEmpty {
            form.addField(name: "language", value: language)
        }
        if !vocabulary.isEmpty {
            // The prompt biases recognition toward these spellings.
            form.addField(name: "prompt", value: "Vocabulary: " + vocabulary.joined(separator: ", "))
        }
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wav)

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        return request
    }

    public func transcribe(wav: Data, vocabulary: [String] = []) async throws -> String {
        let request = makeRequest(wav: wav, vocabulary: vocabulary)
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError where baseURL.isLocalHost && error.code == .cannotConnectToHost {
            throw APIError.unreachable(service: Self.serviceName, url: baseURL.absoluteString,
                                       hint: "Start your local speech-to-text server, or point asrBaseURL at a cloud service.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(service: Self.serviceName, status: response.statusCode,
                                body: String(decoding: data, as: UTF8.self))
        }
        struct Body: Decodable { let text: String }
        do {
            return try JSONDecoder().decode(Body.self, from: data).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw APIError.invalidResponse(service: Self.serviceName,
                                           detail: "no \"text\" field in \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
    }
}
