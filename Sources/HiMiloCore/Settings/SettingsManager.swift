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
                try? SandboxedKeychainHelper.deleteAPIKey()
            } else {
                try? SandboxedKeychainHelper.saveAPIKey(openAIAPIKey)
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
        self.openAIAPIKey = (try? SandboxedKeychainHelper.readAPIKey()) ?? ""
        self.openAIVoice = UserDefaults.standard.string(forKey: "openAIVoice") ?? "onyx"
        self.appleVoiceIdentifier = UserDefaults.standard.string(forKey: "appleVoiceIdentifier")
        self.audioOnly = UserDefaults.standard.bool(forKey: "audioOnly")
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
            return OpenAISpeechEngine(apiKey: openAIAPIKey, voice: openAIVoice)
        }
    }
}
