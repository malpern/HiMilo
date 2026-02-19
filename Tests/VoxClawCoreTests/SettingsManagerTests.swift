@testable import VoxClawCore
import Foundation
import Testing

@MainActor
struct SettingsManagerTests {
    @Test func defaultVoiceEngineIsApple() {
        // Clear any stored value
        UserDefaults.standard.removeObject(forKey: "voiceEngine")
        let settings = SettingsManager()
        #expect(settings.voiceEngine == .apple)
    }

    @Test func defaultOpenAIVoiceIsOnyx() {
        UserDefaults.standard.removeObject(forKey: "openAIVoice")
        let settings = SettingsManager()
        #expect(settings.openAIVoice == "onyx")
    }

    @Test func createEngineReturnsAppleByDefault() {
        UserDefaults.standard.removeObject(forKey: "voiceEngine")
        let settings = SettingsManager()
        let engine = settings.createEngine()
        #expect(engine is AppleSpeechEngine)
    }

    @Test func createEngineFallsBackToAppleWithNoKey() {
        UserDefaults.standard.set("openai", forKey: "voiceEngine")
        defer { UserDefaults.standard.removeObject(forKey: "voiceEngine") }

        let settings = SettingsManager()
        // No API key set, should fall back to Apple
        let engine = settings.createEngine()
        #expect(engine is AppleSpeechEngine)
    }

    @Test func audioOnlyDefaultsFalse() {
        UserDefaults.standard.removeObject(forKey: "audioOnly")
        let settings = SettingsManager()
        #expect(settings.audioOnly == false)
    }
}
