import Foundation
import os
import ServiceManagement

enum VoiceEngineType: String, CaseIterable, Sendable {
    case apple = "apple"
    case openai = "openai"
}

@Observable
@MainActor
final class SettingsManager {
    // Stored properties so @Observable can track changes.
    // Each syncs to UserDefaults/Keychain on write and loads on init.

    var voiceEngine: VoiceEngineType {
        didSet { UserDefaults.standard.set(voiceEngine.rawValue, forKey: "voiceEngine") }
    }

    var openAIAPIKey: String {
        didSet {
            if openAIAPIKey.isEmpty {
                try? KeychainHelper.deleteAPIKey()
            } else {
                try? KeychainHelper.saveAPIKey(openAIAPIKey)
            }
        }
    }

    var openAIVoice: String {
        didSet { UserDefaults.standard.set(openAIVoice, forKey: "openAIVoice") }
    }

    var appleVoiceIdentifier: String? {
        didSet { UserDefaults.standard.set(appleVoiceIdentifier, forKey: "appleVoiceIdentifier") }
    }

    var audioOnly: Bool {
        didSet { UserDefaults.standard.set(audioOnly, forKey: "audioOnly") }
    }

    var networkListenerEnabled: Bool {
        didSet { UserDefaults.standard.set(networkListenerEnabled, forKey: "networkListenerEnabled") }
    }

    var networkListenerPort: UInt16 {
        didSet { UserDefaults.standard.set(Int(networkListenerPort), forKey: "networkListenerPort") }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.settings.error("Launch at login error: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    var isOpenAIConfigured: Bool {
        !openAIAPIKey.isEmpty
    }

    init() {
        self.voiceEngine = VoiceEngineType(rawValue: UserDefaults.standard.string(forKey: "voiceEngine") ?? "apple") ?? .apple
        self.openAIAPIKey = (try? KeychainHelper.readAPIKey()) ?? ""
        self.openAIVoice = UserDefaults.standard.string(forKey: "openAIVoice") ?? "onyx"
        self.appleVoiceIdentifier = UserDefaults.standard.string(forKey: "appleVoiceIdentifier")
        self.audioOnly = UserDefaults.standard.bool(forKey: "audioOnly")
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.networkListenerEnabled = UserDefaults.standard.bool(forKey: "networkListenerEnabled")
        let storedPort = UserDefaults.standard.integer(forKey: "networkListenerPort")
        self.networkListenerPort = storedPort > 0 ? UInt16(storedPort) : 4140
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func createEngine() -> any SpeechEngine {
        switch voiceEngine {
        case .apple:
            return AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier)
        case .openai:
            guard isOpenAIConfigured else {
                Log.settings.info("OpenAI selected but no API key — falling back to Apple")
                return AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier)
            }
            let primary = OpenAISpeechEngine(apiKey: openAIAPIKey, voice: openAIVoice)
            let fallback = AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier)
            return FallbackSpeechEngine(primary: primary, fallback: fallback)
        }
    }
}
