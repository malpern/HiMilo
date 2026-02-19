import Foundation
import Security
import os

/// Keychain helper for the sandboxed App Store version.
/// Uses an app-scoped keychain entry, separate from the CLI's system keychain.
enum SandboxedKeychainHelper {
    private static let service = "com.malpern.voxclaw.openai-api-key"
    private static let account = "openai"

    enum KeychainError: Error {
        case notFound
        case unexpectedData
        case osError(OSStatus)
    }

    static func readAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8), !key.isEmpty else {
                throw KeychainError.unexpectedData
            }
            return key
        case errSecItemNotFound:
            throw KeychainError.notFound
        default:
            throw KeychainError.osError(status)
        }
    }

    static func saveAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else { return }

        // Try to update existing entry first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            // Create new entry
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osError(addStatus)
            }
            Log.settings.info("API key saved to keychain")
        } else if status != errSecSuccess {
            throw KeychainError.osError(status)
        } else {
            Log.settings.info("API key updated in keychain")
        }
    }

    static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osError(status)
        }
    }
}
