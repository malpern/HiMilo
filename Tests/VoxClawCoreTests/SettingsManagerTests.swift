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
        settings.openAIAPIKey = ""  // ensure no key regardless of keychain state
        let engine = settings.createEngine()
        #expect(engine is AppleSpeechEngine)
    }

    @Test func audioOnlyDefaultsFalse() {
        UserDefaults.standard.removeObject(forKey: "audioOnly")
        let settings = SettingsManager()
        #expect(settings.audioOnly == false)
    }

    @Test func pauseOtherAudioDefaultsTrue() {
        UserDefaults.standard.removeObject(forKey: "pauseOtherAudioDuringSpeech")
        let settings = SettingsManager()
        #expect(settings.pauseOtherAudioDuringSpeech == true)
    }

    @Test func voiceSpeedDefaultsToOne() {
        UserDefaults.standard.removeObject(forKey: "voiceSpeed")
        let settings = SettingsManager()
        #expect(settings.voiceSpeed == 1.0)
    }
}
