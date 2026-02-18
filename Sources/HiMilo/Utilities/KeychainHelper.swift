import Foundation
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
                throw KeychainError.unexpectedData
            }
            return key
        case errSecItemNotFound:
            throw KeychainError.notFound
        default:
            throw KeychainError.osError(status)
        }
    }
}
