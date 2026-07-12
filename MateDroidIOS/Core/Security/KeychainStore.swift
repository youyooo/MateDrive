import Foundation
import Security

public protocol SecretStoring: Sendable {
    func get(_ key: String) async throws -> String?
    func set(_ value: String, for key: String) async throws
    func remove(_ key: String) async throws
}

public enum KeychainError: Error, Equatable {
    case unhandledStatus(OSStatus)
    case invalidData
}

public struct KeychainStore: SecretStoring {
    private let service: String
    private let accessGroup: String?

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.matedrive.ios", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func get(_ key: String) async throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.invalidData
        }
        return value
    }

    public func set(_ value: String, for key: String) async throws {
        try await remove(key)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func remove(_ key: String) async throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
