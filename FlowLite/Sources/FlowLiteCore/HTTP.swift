import Foundation

/// Seam for tests: the API clients send requests through this instead of URLSession directly.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(service: request.url?.host ?? "server", detail: "response was not HTTP")
        }
        return (data, http)
    }
}

extension URL {
    /// True for servers on this machine, which usually don't need an API key.
    public var isLocalHost: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}

public enum APIError: LocalizedError, Equatable {
    case missingAPIKey(service: String, hint: String)
    case unreachable(service: String, url: String, hint: String)
    case http(service: String, status: Int, body: String)
    case invalidResponse(service: String, detail: String)
    case refused(category: String?)
    case truncated

    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(service, hint):
            return "\(service) has no API key. \(hint)"
        case let .unreachable(service, url, hint):
            return "\(service) couldn't connect to \(url). \(hint)"
        case let .http(service, status, body):
            let snippet = body.prefix(300)
            let hint = (status == 401 || status == 403) ? " Check the API key." : (status == 429 ? " Rate limited; wait and retry." : "")
            return "\(service) request failed with HTTP \(status).\(hint) Response: \(snippet)"
        case let .invalidResponse(service, detail):
            return "\(service) returned an unexpected response: \(detail)"
        case let .refused(category):
            return "Claude declined to clean up this text (category: \(category ?? "unspecified"))."
        case .truncated:
            return "Cleanup hit the model's output limit before finishing."
        }
    }
}

/// Builds a multipart/form-data body for file uploads.
public struct MultipartForm {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "FlowLite-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    public mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    public func finalized() -> Data {
        var result = body
        result.append(contentsOf: Array("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ text: String) {
        body.append(contentsOf: Array(text.utf8))
    }
}
