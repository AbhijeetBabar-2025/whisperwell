import Foundation
import Security

/// Where API keys live. The app uses the macOS Keychain; tests use `InMemorySecretStore`.
public protocol SecretStore: Sendable {
    func get(_ name: String) throws -> String?
    /// Saves `value` under `name`; nil or empty deletes it.
    func set(_ name: String, _ value: String?) throws
}

/// API keys as generic passwords in the user's login keychain.
public struct KeychainStore: SecretStore {
    public static let shared = KeychainStore(service: "Whisperwell")
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    public func get(_ name: String) throws -> String? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(action: "read", name: name, status: status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func set(_ name: String, _ value: String?) throws {
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query(name) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(action: "delete", name: name, status: status)
            }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(name)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "\(service) \(name)"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError(action: "save", name: name, status: status)
        }
    }
}

public struct KeychainError: LocalizedError, Equatable {
    public let action: String
    public let name: String
    public let status: OSStatus

    public var errorDescription: String? {
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Couldn't \(action) \(name) in the Keychain: \(reason). Open Keychain Access, check the \"Whisperwell\" items, and try again."
    }
}

/// Keeps keys in memory. For tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func get(_ name: String) throws -> String? {
        lock.withLock { values[name] }
    }

    public func set(_ name: String, _ value: String?) throws {
        lock.withLock { values[name] = (value?.isEmpty ?? true) ? nil : value }
    }
}
