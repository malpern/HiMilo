import Foundation
import os
import Security

enum KeychainHelper {
    enum KeychainError: Error, CustomStringConvertible {
        case notFound
        case unexpectedData
        case osError(OSStatus)

        var description: String {
            switch self {
            case .notFound:
                return "API key not found in Keychain. Add it with:\n  security add-generic-password -a \"openai\" -s \"openai-voice-api-key\" -w \"sk-...\""
            case .unexpectedData:
                return "Unexpected data format in Keychain entry"
            case .osError(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    static func readAPIKey() throws -> String {
        // First check environment variable
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            Log.keychain.info("API key sourced from OPENAI_API_KEY env var")
            return envKey
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "openai",
            kSecAttrService as String: "openai-voice-api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8), !key.isEmpty else {
                Log.keychain.error("Keychain returned unexpected data format")
                throw KeychainError.unexpectedData
            }
            Log.keychain.info("API key sourced from Keychain")
            return key
        case errSecItemNotFound:
            Log.keychain.error("API key not found in Keychain")
            throw KeychainError.notFound
        default:
            Log.keychain.error("Keychain error: status=\(status, privacy: .public)")
            throw KeychainError.osError(status)
        }
    }
}
