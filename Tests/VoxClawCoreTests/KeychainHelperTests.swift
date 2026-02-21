import Foundation
@testable import VoxClawCore
import Testing

@Suite(.serialized)
struct KeychainHelperTests {
    // Isolated service name so tests never touch the real keychain entry
    private let service = "voxclaw-test-keychain"
    private let account = "test"

    /// Save a key, read it back, verify it matches.
    @Test func saveAndReadRoundTrip() throws {
        defer { try? KeychainHelper.deleteAPIKey(service: service, account: account) }

        let testKey = "sk-test-roundtrip-\(UUID().uuidString)"
        try KeychainHelper.saveAPIKey(testKey, service: service, account: account)

        let readBack = try KeychainHelper.readFromKeychain(service: service, account: account)
        #expect(readBack == testKey)
    }

    /// Saving a second key overwrites the first.
    @Test func saveOverwritesPreviousKey() throws {
        defer { try? KeychainHelper.deleteAPIKey(service: service, account: account) }

        try KeychainHelper.saveAPIKey("sk-first", service: service, account: account)
        try KeychainHelper.saveAPIKey("sk-second", service: service, account: account)

        let readBack = try KeychainHelper.readFromKeychain(service: service, account: account)
        #expect(readBack == "sk-second")
    }

    /// Deleting removes the key so the next read throws.
    @Test func deleteRemovesKey() throws {
        defer { try? KeychainHelper.deleteAPIKey(service: service, account: account) }

        try KeychainHelper.saveAPIKey("sk-to-delete", service: service, account: account)
        try KeychainHelper.deleteAPIKey(service: service, account: account)

        #expect(throws: KeychainHelper.KeychainError.self) {
            try KeychainHelper.readFromKeychain(service: service, account: account)
        }
    }

    @Test func normalizeAcceptsLikelyOpenAIKey() {
        let key = "  sk-test-roundtrip-\(UUID().uuidString)  "
        let normalized = KeychainHelper.normalizedIfLikelyOpenAIKey(key)
        #expect(normalized == key.trimmingCharacters(in: .whitespaces))
    }

    @Test func normalizeRejectsNonOpenAIKey() {
        #expect(KeychainHelper.normalizedIfLikelyOpenAIKey("not-a-key") == nil)
        #expect(KeychainHelper.normalizedIfLikelyOpenAIKey("sk-short") == nil)
    }
}
