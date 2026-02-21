import Foundation
import os
import Security

enum KeychainHelper {
    private static let defaultService = "openai-voice-api-key"
    private static let defaultAccount = "openai"
    private struct LegacyKeychainCandidate {
        let service: String
        let preferredAccounts: [String]
    }
    private static let legacyServiceCandidates: [LegacyKeychainCandidate] = [
        LegacyKeychainCandidate(
            service: "openclaw.OPENAI_API_KEY",
            preferredAccounts: ["openai", "openclaw"]
        ),
        LegacyKeychainCandidate(
            service: "OPENAI_API_KEY",
            preferredAccounts: ["openai"]
        ),
    ]

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

    /// Reads API key, checking the `OPENAI_API_KEY` env var first, then keychain.
    static func readAPIKey() throws -> String {
        // First check environment variable
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"].map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }), !envKey.isEmpty {
            Log.keychain.info("API key sourced from OPENAI_API_KEY env var")
            return envKey
        }

        return try readFromKeychain()
    }

    /// Reads API key directly from the keychain, bypassing the env var check.
    static func readFromKeychain(service: String = defaultService, account: String = defaultAccount) throws -> String {
        try readFromKeychain(service: service, account: Optional(account))
    }

    /// Reads API key directly from keychain with optional account filtering.
    static func readFromKeychain(service: String, account: String?) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var queryWithAccount = query
        if let account {
            queryWithAccount[kSecAttrAccount as String] = account
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(queryWithAccount as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let raw = String(data: data, encoding: .utf8) else {
                Log.keychain.error("Keychain returned unexpected data format")
                throw KeychainError.unexpectedData
            }
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
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

    static func readAllFromKeychain(service: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            if let single = result as? Data,
               let raw = String(data: single, encoding: .utf8),
               let key = normalizedIfLikelyOpenAIKey(raw) {
                return [key]
            }
            guard let dataArray = result as? [Data] else {
                throw KeychainError.unexpectedData
            }
            return dataArray.compactMap { data in
                guard let raw = String(data: data, encoding: .utf8) else { return nil }
                return normalizedIfLikelyOpenAIKey(raw)
            }
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError.osError(status)
        }
    }

    static func normalizedIfLikelyOpenAIKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20 else { return nil }
        return key
    }

    /// Reads API key from the default location, falling back to legacy service names.
    /// If a legacy entry is found, it is migrated into the default VoxClaw keychain item.
    static func readPersistedAPIKey() throws -> String {
        if let key = try? readFromKeychain() {
            return key
        }

        for candidate in legacyServiceCandidates {
            for account in candidate.preferredAccounts {
                if let key = try? readFromKeychain(service: candidate.service, account: account),
                   let normalized = normalizedIfLikelyOpenAIKey(key) {
                    try? saveAPIKey(normalized)
                    Log.keychain.info("Migrated API key from legacy keychain service \(candidate.service, privacy: .public) with account \(account, privacy: .public)")
                    return normalized
                }
            }

            let uniqueKeys = Set((try? readAllFromKeychain(service: candidate.service)) ?? [])
            if uniqueKeys.count == 1, let key = uniqueKeys.first {
                try? saveAPIKey(key)
                Log.keychain.info("Migrated unique API key from legacy keychain service: \(candidate.service, privacy: .public)")
                return key
            }
            if uniqueKeys.count > 1 {
                Log.keychain.warning("Skipped legacy key migration for \(candidate.service, privacy: .public): multiple candidate keys found")
            }
        }

        throw KeychainError.notFound
    }

    static func saveAPIKey(_ key: String, service: String = defaultService, account: String = defaultAccount) throws {
        guard let data = key.data(using: .utf8) else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecValueData as String: data,
        ]
        var status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Entry already exists — update it in place
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: service,
            ]
            status = SecItemUpdate(searchQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainError.osError(status)
        }
        Log.keychain.info("API key saved to keychain")
    }

    static func deleteAPIKey(service: String = defaultService, account: String = defaultAccount) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osError(status)
        }
    }
}
