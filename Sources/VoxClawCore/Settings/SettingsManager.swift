import Foundation
import os
#if os(macOS)
import ServiceManagement
#endif

public enum VoiceEngineType: String, CaseIterable, Sendable {
    case apple = "apple"
    case openai = "openai"
}

@Observable
@MainActor
public final class SettingsManager {
    // Stored properties so @Observable can track changes.
    // Each syncs to UserDefaults/Keychain on write and loads on init.

    public var voiceEngine: VoiceEngineType {
        didSet { UserDefaults.standard.set(voiceEngine.rawValue, forKey: "voiceEngine") }
    }

    public var openAIAPIKey: String {
        didSet {
            if openAIAPIKey.isEmpty {
                try? KeychainHelper.deleteAPIKey()
            } else {
                try? KeychainHelper.saveAPIKey(openAIAPIKey)
            }
        }
    }

    public var openAIVoice: String {
        didSet { UserDefaults.standard.set(openAIVoice, forKey: "openAIVoice") }
    }

    public var appleVoiceIdentifier: String? {
        didSet { UserDefaults.standard.set(appleVoiceIdentifier, forKey: "appleVoiceIdentifier") }
    }

    public var readingStyle: String {
        didSet { UserDefaults.standard.set(readingStyle, forKey: "readingStyle") }
    }

    public var audioOnly: Bool {
        didSet { UserDefaults.standard.set(audioOnly, forKey: "audioOnly") }
    }

    public var pauseOtherAudioDuringSpeech: Bool {
        didSet { UserDefaults.standard.set(pauseOtherAudioDuringSpeech, forKey: "pauseOtherAudioDuringSpeech") }
    }

    public var networkListenerEnabled: Bool {
        didSet { UserDefaults.standard.set(networkListenerEnabled, forKey: "networkListenerEnabled") }
    }

    public var networkListenerPort: UInt16 {
        didSet { UserDefaults.standard.set(Int(networkListenerPort), forKey: "networkListenerPort") }
    }

    public var backgroundKeepAlive: Bool {
        didSet { UserDefaults.standard.set(backgroundKeepAlive, forKey: "backgroundKeepAlive") }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    public var overlayAppearance: OverlayAppearance {
        didSet {
            if let data = try? JSONEncoder().encode(overlayAppearance) {
                UserDefaults.standard.set(data, forKey: "overlayAppearance")
            }
        }
    }

    #if os(macOS)
    public var launchAtLogin: Bool {
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
    #endif

    public var isOpenAIConfigured: Bool {
        !openAIAPIKey.isEmpty
    }

    public init() {
        self.voiceEngine = VoiceEngineType(rawValue: UserDefaults.standard.string(forKey: "voiceEngine") ?? "apple") ?? .apple
        // Pull latest from iCloud KVS before reading the key.
        NSUbiquitousKeyValueStore.default.synchronize()
        // App settings should reflect the key explicitly saved in VoxClaw.
        // Avoid env-var override here so stale shell/launchd vars can't shadow Settings.
        let loadedKey = (try? KeychainHelper.readPersistedAPIKey()) ?? ""
        self.openAIAPIKey = loadedKey
        self.openAIVoice = UserDefaults.standard.string(forKey: "openAIVoice") ?? "onyx"
        self.appleVoiceIdentifier = UserDefaults.standard.string(forKey: "appleVoiceIdentifier")
        self.readingStyle = UserDefaults.standard.string(forKey: "readingStyle") ?? ""
        self.audioOnly = UserDefaults.standard.bool(forKey: "audioOnly")
        if UserDefaults.standard.object(forKey: "pauseOtherAudioDuringSpeech") == nil {
            self.pauseOtherAudioDuringSpeech = true
        } else {
            self.pauseOtherAudioDuringSpeech = UserDefaults.standard.bool(forKey: "pauseOtherAudioDuringSpeech")
        }
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.networkListenerEnabled = UserDefaults.standard.bool(forKey: "networkListenerEnabled")
        let storedPort = UserDefaults.standard.integer(forKey: "networkListenerPort")
        self.networkListenerPort = storedPort > 0 ? UInt16(storedPort) : 4140
        if UserDefaults.standard.object(forKey: "backgroundKeepAlive") == nil {
            self.backgroundKeepAlive = true
        } else {
            self.backgroundKeepAlive = UserDefaults.standard.bool(forKey: "backgroundKeepAlive")
        }
        #if os(macOS)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        #endif

        if let data = UserDefaults.standard.data(forKey: "overlayAppearance"),
           let decoded = try? JSONDecoder().decode(OverlayAppearance.self, from: data) {
            self.overlayAppearance = decoded
        } else {
            self.overlayAppearance = OverlayAppearance()
        }

        // Seed KVS if we have a local key but KVS is empty (e.g. first launch after upgrade).
        if !loadedKey.isEmpty {
            KeychainHelper.seedKVSIfNeeded(loadedKey)
        }

        observeICloudKVSChanges()
    }

    // MARK: - iCloud KVS Observation

    private func observeICloudKVSChanges() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                  changedKeys.contains("openai-api-key") else {
                return
            }
            let newKey = NSUbiquitousKeyValueStore.default.string(forKey: "openai-api-key")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor [weak self] in
                guard let self, newKey != self.openAIAPIKey else { return }
                // Save locally without triggering didSet's KVS write (already in KVS)
                if newKey.isEmpty {
                    try? KeychainHelper.deleteAPIKey()
                } else {
                    try? KeychainHelper.saveAPIKey(newKey)
                }
                self.openAIAPIKey = newKey
                Log.settings.info("API key updated from iCloud KVS")
            }
        }
    }

    public func createEngine(instructionsOverride: String? = nil) -> any SpeechEngine {
        let instructions = instructionsOverride ?? (readingStyle.isEmpty ? nil : readingStyle)
        switch voiceEngine {
        case .apple:
            return AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier)
        case .openai:
            guard isOpenAIConfigured else {
                Log.settings.info("OpenAI selected but no API key — falling back to Apple")
                NotificationCenter.default.post(name: .voxClawOpenAIKeyMissing, object: nil)
                return AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier)
            }
            let primary = OpenAISpeechEngine(apiKey: openAIAPIKey, voice: openAIVoice, instructions: instructions)
            let fallback = AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier)
            return FallbackSpeechEngine(primary: primary, fallback: fallback)
        }
    }
}
