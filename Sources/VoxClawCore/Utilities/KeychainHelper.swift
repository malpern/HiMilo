import Foundation
import Synchronization
import os
#if os(macOS)
import Security
#endif

public enum KeychainHelper {
    /// Override for testing — set to a temp directory to isolate from real storage.
    private static let _storageDirectoryOverride = Mutex<URL?>(nil)
    static var storageDirectoryOverride: URL? {
        get { _storageDirectoryOverride.withLock { $0 } }
        set { _storageDirectoryOverride.withLock { $0 = newValue } }
    }

    private static let kvsKey = "openai-api-key"
    private static let elevenLabsKvsKey = "elevenlabs-api-key"

    private static var storageDirectory: URL {
        if let override = storageDirectoryOverride { return override }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoxClaw")
    }

    private static var apiKeyFileURL: URL {
        storageDirectory.appendingPathComponent("api-key")
    }

    private static var elevenLabsKeyFileURL: URL {
        storageDirectory.appendingPathComponent("elevenlabs-api-key")
    }

    enum KeychainError: Error, CustomStringConvertible {
        case notFound
        case unexpectedData
        case fileError(Error)

        var description: String {
            switch self {
            case .notFound:
                return "API key not found. Set it in VoxClaw Settings or via the OPENAI_API_KEY environment variable."
            case .unexpectedData:
                return "Unexpected data format in stored API key"
            case .fileError(let error):
                return "File storage error: \(error.localizedDescription)"
            }
        }
    }

    /// Reads API key, checking the `OPENAI_API_KEY` env var first, then file storage.
    public static func readAPIKey() throws -> String {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
           !envKey.isEmpty {
            Log.keychain.info("API key sourced from OPENAI_API_KEY env var")
            return envKey
        }
        return try readPersistedAPIKey()
    }

    /// Reads API key from file storage, migrating from Keychain on first access if needed.
    /// Falls back to iCloud KVS if no local copy exists.
    public static func readPersistedAPIKey() throws -> String {
        // 1. Try file storage first
        if let key = readFromFile() {
            return key
        }

        // 2. One-time migration from Keychain (skip when storageDirectoryOverride is set, i.e. tests)
        #if os(macOS)
        if storageDirectoryOverride == nil, let key = migrateFromKeychain() {
            return key
        }
        #endif

        // 3. Try iCloud KVS as fallback (skip in test mode)
        if storageDirectoryOverride == nil, let key = readFromKVS() {
            // Save locally so we don't need KVS next time
            try? saveToFile(key)
            Log.keychain.info("API key restored from iCloud KVS")
            return key
        }

        throw KeychainError.notFound
    }

    public static func saveAPIKey(_ key: String) throws {
        try saveToFile(key)
        saveToKVS(key)
    }

    public static func deleteAPIKey() throws {
        let fileURL = apiKeyFileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            Log.keychain.info("API key deleted from file storage")
        }
        removeFromKVS()
    }

    // MARK: - ElevenLabs API Key

    /// Reads ElevenLabs API key, checking the `ELEVENLABS_API_KEY` env var first, then file storage.
    public static func readElevenLabsAPIKey() throws -> String {
        if let envKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
           !envKey.isEmpty {
            Log.keychain.info("ElevenLabs API key sourced from ELEVENLABS_API_KEY env var")
            return envKey
        }
        return try readPersistedElevenLabsAPIKey()
    }

    public static func readPersistedElevenLabsAPIKey() throws -> String {
        // 1. Try file storage
        if let key = readElevenLabsFromFile() {
            return key
        }

        // 2. Try iCloud KVS as fallback (skip in test mode)
        if storageDirectoryOverride == nil, let key = readElevenLabsFromKVS() {
            try? saveElevenLabsToFile(key)
            Log.keychain.info("ElevenLabs API key restored from iCloud KVS")
            return key
        }

        throw KeychainError.notFound
    }

    public static func saveElevenLabsAPIKey(_ key: String) throws {
        try saveElevenLabsToFile(key)
        saveElevenLabsToKVS(key)
    }

    public static func deleteElevenLabsAPIKey() throws {
        let fileURL = elevenLabsKeyFileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            Log.keychain.info("ElevenLabs API key deleted from file storage")
        }
        removeElevenLabsFromKVS()
    }

    private static func saveElevenLabsToFile(_ key: String) throws {
        let dir = storageDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = elevenLabsKeyFileURL
        try key.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        Log.keychain.info("ElevenLabs API key saved to file storage")
    }

    private static func readElevenLabsFromFile() -> String? {
        let fileURL = elevenLabsKeyFileURL
        guard let data = FileManager.default.contents(atPath: fileURL.path),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        Log.keychain.info("ElevenLabs API key sourced from file storage")
        return key
    }

    private static func saveElevenLabsToKVS(_ key: String) {
        guard storageDirectoryOverride == nil else { return }
        NSUbiquitousKeyValueStore.default.set(key, forKey: elevenLabsKvsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        Log.keychain.info("ElevenLabs API key synced to iCloud KVS")
    }

    private static func readElevenLabsFromKVS() -> String? {
        NSUbiquitousKeyValueStore.default.synchronize()
        guard let raw = NSUbiquitousKeyValueStore.default.string(forKey: elevenLabsKvsKey) else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return key
    }

    private static func removeElevenLabsFromKVS() {
        guard storageDirectoryOverride == nil else { return }
        NSUbiquitousKeyValueStore.default.removeObject(forKey: elevenLabsKvsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        Log.keychain.info("ElevenLabs API key removed from iCloud KVS")
    }

    // MARK: - File Storage

    private static func saveToFile(_ key: String) throws {
        let dir = storageDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = apiKeyFileURL
        try key.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        Log.keychain.info("API key saved to file storage")
    }

    private static func readFromFile() -> String? {
        let fileURL = apiKeyFileURL
        guard let data = FileManager.default.contents(atPath: fileURL.path),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        Log.keychain.info("API key sourced from file storage")
        return key
    }

    /// Push a local key to KVS if KVS is currently empty (first launch after upgrade).
    public static func seedKVSIfNeeded(_ key: String) {
        guard storageDirectoryOverride == nil else { return }
        if readFromKVS() == nil {
            saveToKVS(key)
            Log.keychain.info("Seeded iCloud KVS with existing local API key")
        }
    }

    // MARK: - iCloud KVS

    private static func saveToKVS(_ key: String) {
        guard storageDirectoryOverride == nil else { return }
        NSUbiquitousKeyValueStore.default.set(key, forKey: kvsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        Log.keychain.info("API key synced to iCloud KVS")
    }

    private static func readFromKVS() -> String? {
        NSUbiquitousKeyValueStore.default.synchronize()
        guard let raw = NSUbiquitousKeyValueStore.default.string(forKey: kvsKey) else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return key
    }

    private static func removeFromKVS() {
        guard storageDirectoryOverride == nil else { return }
        NSUbiquitousKeyValueStore.default.removeObject(forKey: kvsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        Log.keychain.info("API key removed from iCloud KVS")
    }

    #if os(macOS)
    // MARK: - One-Time Keychain Migration

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

    /// Attempts to read from Keychain (default + legacy locations) and migrate to file storage.
    private static func migrateFromKeychain() -> String? {
        // Try default VoxClaw keychain entry
        if let key = try? readFromKeychain(service: defaultService, account: defaultAccount) {
            try? saveAPIKey(key)
            Log.keychain.info("Migrated API key from Keychain to file storage")
            return key
        }

        // Try legacy service names
        for candidate in legacyServiceCandidates {
            for account in candidate.preferredAccounts {
                if let key = try? readFromKeychain(service: candidate.service, account: account),
                   let normalized = normalizedIfLikelyOpenAIKey(key) {
                    try? saveAPIKey(normalized)
                    Log.keychain.info("Migrated API key from legacy Keychain service \(candidate.service, privacy: .public)")
                    return normalized
                }
            }

            let allKeys = (try? readAllFromKeychain(service: candidate.service)) ?? []
            if let key = uniqueMigrationKey(from: allKeys) {
                try? saveAPIKey(key)
                Log.keychain.info("Migrated unique API key from legacy Keychain service: \(candidate.service, privacy: .public)")
                return key
            }
        }

        return nil
    }

    private static func readFromKeychain(service: String, account: String) throws -> String {
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
                  let raw = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw KeychainError.unexpectedData }
            return key
        default:
            throw KeychainError.notFound
        }
    }

    private static func readAllFromKeychain(service: String) throws -> [String] {
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
        default:
            return []
        }
    }
    #endif

    // MARK: - Helpers

    static func normalizedIfLikelyOpenAIKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20 else { return nil }
        return key
    }

    static func uniqueMigrationKey(from keys: [String]) -> String? {
        let normalized = keys.compactMap(normalizedIfLikelyOpenAIKey)
        let unique = Set(normalized)
        guard unique.count == 1 else { return nil }
        return unique.first
    }
}
