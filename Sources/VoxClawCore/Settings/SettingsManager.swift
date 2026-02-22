import Foundation
import os
#if os(macOS)
import ServiceManagement
#endif

public enum VoiceEngineType: String, CaseIterable, Sendable {
    case apple = "apple"
    case openai = "openai"
    case elevenlabs = "elevenlabs"
}

@Observable
@MainActor
public final class SettingsManager {
    // Stored properties so @Observable can track changes.
    // Each syncs to UserDefaults/Keychain on write and loads on init.

    public var voiceEngine: VoiceEngineType {
        didSet {
            UserDefaults.standard.set(voiceEngine.rawValue, forKey: "voiceEngine")
            NSUbiquitousKeyValueStore.default.set(voiceEngine.rawValue, forKey: "voiceEngine")
        }
    }

    public var openAIAPIKey: String {
        didSet {
            do {
                if openAIAPIKey.isEmpty {
                    try KeychainHelper.deleteAPIKey()
                } else {
                    try KeychainHelper.saveAPIKey(openAIAPIKey)
                }
            } catch {
                Log.settings.error("Failed to persist API key: \(error)")
            }
        }
    }

    public var openAIVoice: String {
        didSet {
            UserDefaults.standard.set(openAIVoice, forKey: "openAIVoice")
            NSUbiquitousKeyValueStore.default.set(openAIVoice, forKey: "openAIVoice")
        }
    }

    public var elevenLabsAPIKey: String {
        didSet {
            do {
                if elevenLabsAPIKey.isEmpty {
                    try KeychainHelper.deleteElevenLabsAPIKey()
                } else {
                    try KeychainHelper.saveElevenLabsAPIKey(elevenLabsAPIKey)
                }
            } catch {
                Log.settings.error("Failed to persist ElevenLabs API key: \(error)")
            }
        }
    }

    public var elevenLabsVoiceID: String {
        didSet {
            UserDefaults.standard.set(elevenLabsVoiceID, forKey: "elevenLabsVoiceID")
            NSUbiquitousKeyValueStore.default.set(elevenLabsVoiceID, forKey: "elevenLabsVoiceID")
        }
    }

    public var elevenLabsTurbo: Bool {
        didSet {
            UserDefaults.standard.set(elevenLabsTurbo, forKey: "elevenLabsTurbo")
            NSUbiquitousKeyValueStore.default.set(elevenLabsTurbo, forKey: "elevenLabsTurbo")
        }
    }

    public var appleVoiceIdentifier: String? {
        didSet { UserDefaults.standard.set(appleVoiceIdentifier, forKey: "appleVoiceIdentifier") }
    }

    public var readingStyle: String {
        didSet { UserDefaults.standard.set(readingStyle, forKey: "readingStyle") }
    }

    public var voiceSpeed: Float {
        didSet {
            UserDefaults.standard.set(voiceSpeed, forKey: "voiceSpeed")
            NSUbiquitousKeyValueStore.default.set(Double(voiceSpeed), forKey: "voiceSpeed")
        }
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

    public var rememberOverlayPosition: Bool {
        didSet { UserDefaults.standard.set(rememberOverlayPosition, forKey: "rememberOverlayPosition") }
    }

    public var savedOverlayOrigin: CGPoint? {
        didSet {
            if let origin = savedOverlayOrigin {
                UserDefaults.standard.set(origin.x, forKey: "savedOverlayOriginX")
                UserDefaults.standard.set(origin.y, forKey: "savedOverlayOriginY")
            } else {
                UserDefaults.standard.removeObject(forKey: "savedOverlayOriginX")
                UserDefaults.standard.removeObject(forKey: "savedOverlayOriginY")
            }
        }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    public var overlayAppearance: OverlayAppearance {
        didSet {
            do {
                let data = try JSONEncoder().encode(overlayAppearance)
                UserDefaults.standard.set(data, forKey: "overlayAppearance")
                NSUbiquitousKeyValueStore.default.set(data, forKey: "overlayAppearance")
            } catch {
                Log.settings.error("Failed to encode overlay appearance: \(error)")
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

    public var isElevenLabsConfigured: Bool {
        !elevenLabsAPIKey.isEmpty
    }

    public init() {
        // Pull latest from iCloud KVS before reading any settings.
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        // Prefer KVS value for synced settings, falling back to UserDefaults.
        if let kvsEngine = kvs.string(forKey: "voiceEngine"),
           UserDefaults.standard.string(forKey: "voiceEngine") == nil {
            self.voiceEngine = VoiceEngineType(rawValue: kvsEngine) ?? .apple
        } else {
            self.voiceEngine = VoiceEngineType(rawValue: UserDefaults.standard.string(forKey: "voiceEngine") ?? "apple") ?? .apple
        }

        // App settings should reflect the key explicitly saved in VoxClaw.
        // Avoid env-var override here so stale shell/launchd vars can't shadow Settings.
        let loadedKey = (try? KeychainHelper.readPersistedAPIKey()) ?? ""
        self.openAIAPIKey = loadedKey

        self.openAIVoice = kvs.string(forKey: "openAIVoice")
            ?? UserDefaults.standard.string(forKey: "openAIVoice")
            ?? "onyx"

        let loadedElevenLabsKey = (try? KeychainHelper.readPersistedElevenLabsAPIKey()) ?? ""
        self.elevenLabsAPIKey = loadedElevenLabsKey

        self.elevenLabsVoiceID = kvs.string(forKey: "elevenLabsVoiceID")
            ?? UserDefaults.standard.string(forKey: "elevenLabsVoiceID")
            ?? "JBFqnCBsd6RMkjVDRZzb"

        // KVS stores bools as numbers; check if key exists before using.
        if kvs.object(forKey: "elevenLabsTurbo") != nil {
            self.elevenLabsTurbo = kvs.bool(forKey: "elevenLabsTurbo")
        } else {
            self.elevenLabsTurbo = UserDefaults.standard.bool(forKey: "elevenLabsTurbo")
        }

        self.appleVoiceIdentifier = UserDefaults.standard.string(forKey: "appleVoiceIdentifier")
        self.readingStyle = UserDefaults.standard.string(forKey: "readingStyle") ?? ""

        let kvsSpeed = kvs.double(forKey: "voiceSpeed")
        let storedSpeed = UserDefaults.standard.float(forKey: "voiceSpeed")
        if kvsSpeed > 0 {
            self.voiceSpeed = Float(kvsSpeed)
        } else {
            self.voiceSpeed = storedSpeed > 0 ? storedSpeed : 1.0
        }
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
        self.rememberOverlayPosition = UserDefaults.standard.bool(forKey: "rememberOverlayPosition")
        if UserDefaults.standard.object(forKey: "savedOverlayOriginX") != nil {
            let x = UserDefaults.standard.double(forKey: "savedOverlayOriginX")
            let y = UserDefaults.standard.double(forKey: "savedOverlayOriginY")
            self.savedOverlayOrigin = CGPoint(x: x, y: y)
        } else {
            self.savedOverlayOrigin = nil
        }
        #if os(macOS)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        #endif

        // Overlay appearance: prefer KVS data, then UserDefaults
        if let data = kvs.data(forKey: "overlayAppearance"),
           let decoded = try? JSONDecoder().decode(OverlayAppearance.self, from: data) {
            self.overlayAppearance = decoded
        } else if let data = UserDefaults.standard.data(forKey: "overlayAppearance"),
                  let decoded = try? JSONDecoder().decode(OverlayAppearance.self, from: data) {
            self.overlayAppearance = decoded
        } else {
            self.overlayAppearance = OverlayAppearance()
        }

        // Seed KVS if we have a local key but KVS is empty (e.g. first launch after upgrade).
        if !loadedKey.isEmpty {
            KeychainHelper.seedKVSIfNeeded(loadedKey)
        }
        if !loadedElevenLabsKey.isEmpty {
            KeychainHelper.seedElevenLabsKVSIfNeeded(loadedElevenLabsKey)
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
            guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
                return
            }
            let kvs = NSUbiquitousKeyValueStore.default

            Task { @MainActor [weak self] in
                guard let self else { return }

                // OpenAI API key
                if changedKeys.contains("openai-api-key") {
                    let newKey = kvs.string(forKey: "openai-api-key")?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if newKey != self.openAIAPIKey {
                        do {
                            if newKey.isEmpty {
                                try KeychainHelper.deleteAPIKey()
                            } else {
                                try KeychainHelper.saveAPIKey(newKey)
                            }
                        } catch {
                            Log.settings.error("Failed to persist iCloud KVS OpenAI key locally: \(error)")
                        }
                        self.openAIAPIKey = newKey
                        Log.settings.info("OpenAI API key updated from iCloud KVS")
                    }
                }

                // ElevenLabs API key
                if changedKeys.contains("elevenlabs-api-key") {
                    let newKey = kvs.string(forKey: "elevenlabs-api-key")?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if newKey != self.elevenLabsAPIKey {
                        do {
                            if newKey.isEmpty {
                                try KeychainHelper.deleteElevenLabsAPIKey()
                            } else {
                                try KeychainHelper.saveElevenLabsAPIKey(newKey)
                            }
                        } catch {
                            Log.settings.error("Failed to persist iCloud KVS ElevenLabs key locally: \(error)")
                        }
                        self.elevenLabsAPIKey = newKey
                        Log.settings.info("ElevenLabs API key updated from iCloud KVS")
                    }
                }

                // Voice engine
                if changedKeys.contains("voiceEngine"),
                   let raw = kvs.string(forKey: "voiceEngine"),
                   let engine = VoiceEngineType(rawValue: raw),
                   engine != self.voiceEngine {
                    self.voiceEngine = engine
                    Log.settings.info("Voice engine updated from iCloud KVS: \(raw)")
                }

                // OpenAI voice
                if changedKeys.contains("openAIVoice"),
                   let voice = kvs.string(forKey: "openAIVoice"),
                   voice != self.openAIVoice {
                    self.openAIVoice = voice
                    Log.settings.info("OpenAI voice updated from iCloud KVS")
                }

                // ElevenLabs voice ID
                if changedKeys.contains("elevenLabsVoiceID"),
                   let voiceID = kvs.string(forKey: "elevenLabsVoiceID"),
                   voiceID != self.elevenLabsVoiceID {
                    self.elevenLabsVoiceID = voiceID
                    Log.settings.info("ElevenLabs voice updated from iCloud KVS")
                }

                // ElevenLabs turbo
                if changedKeys.contains("elevenLabsTurbo") {
                    let turbo = kvs.bool(forKey: "elevenLabsTurbo")
                    if turbo != self.elevenLabsTurbo {
                        self.elevenLabsTurbo = turbo
                        Log.settings.info("ElevenLabs turbo updated from iCloud KVS")
                    }
                }

                // Voice speed
                if changedKeys.contains("voiceSpeed") {
                    let speed = Float(kvs.double(forKey: "voiceSpeed"))
                    if speed > 0, speed != self.voiceSpeed {
                        self.voiceSpeed = speed
                        Log.settings.info("Voice speed updated from iCloud KVS")
                    }
                }

                // Overlay appearance
                if changedKeys.contains("overlayAppearance"),
                   let data = kvs.data(forKey: "overlayAppearance"),
                   let decoded = try? JSONDecoder().decode(OverlayAppearance.self, from: data) {
                    self.overlayAppearance = decoded
                    Log.settings.info("Overlay appearance updated from iCloud KVS")
                }
            }
        }
    }

    public func createEngine(instructionsOverride: String? = nil) -> any SpeechEngine {
        let instructions = instructionsOverride ?? (readingStyle.isEmpty ? nil : readingStyle)
        switch voiceEngine {
        case .apple:
            return AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier, rate: voiceSpeed)
        case .openai:
            guard isOpenAIConfigured else {
                Log.settings.info("OpenAI selected but no API key — falling back to Apple")
                voiceEngine = .apple
                NotificationCenter.default.post(name: .voxClawOpenAIKeyMissing, object: nil)
                return AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier, rate: voiceSpeed)
            }
            let primary = OpenAISpeechEngine(apiKey: openAIAPIKey, voice: openAIVoice, speed: voiceSpeed, instructions: instructions)
            let fallback = AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier, rate: voiceSpeed)
            return FallbackSpeechEngine(primary: primary, fallback: fallback)
        case .elevenlabs:
            guard isElevenLabsConfigured else {
                Log.settings.info("ElevenLabs selected but no API key — falling back to Apple")
                voiceEngine = .apple
                return AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier, rate: voiceSpeed)
            }
            let primary = ElevenLabsSpeechEngine(apiKey: elevenLabsAPIKey, voiceID: elevenLabsVoiceID, speed: voiceSpeed, turbo: elevenLabsTurbo)
            let fallback = AppleSpeechEngine(voiceIdentifier: appleVoiceIdentifier, rate: voiceSpeed)
            return FallbackSpeechEngine(primary: primary, fallback: fallback)
        }
    }
}
