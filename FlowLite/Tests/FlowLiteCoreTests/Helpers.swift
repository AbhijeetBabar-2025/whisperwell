import Foundation
@testable import FlowLiteCore

/// Records requests and replies with a canned response.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    let status: Int
    let body: Data

    init(status: Int = 200, json: String) {
        self.status = status
        body = Data(json.utf8)
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }
}

func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
}
