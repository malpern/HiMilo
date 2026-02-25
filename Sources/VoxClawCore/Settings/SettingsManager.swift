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
    private enum KVSKey {
        static let voiceEngine = "voiceEngine"
        static let openAIVoice = "openAIVoice"
        static let elevenLabsVoiceID = "elevenLabsVoiceID"
        static let elevenLabsTurbo = "elevenLabsTurbo"
        static let appleVoiceIdentifier = "appleVoiceIdentifier"
        static let readingStyle = "readingStyle"
        static let voiceSpeed = "voiceSpeed"
        static let audioOnly = "audioOnly"
        static let pauseOtherAudioDuringSpeech = "pauseOtherAudioDuringSpeech"
        static let networkListenerEnabled = "networkListenerEnabled"
        static let networkListenerPort = "networkListenerPort"
        static let networkBindMode = "networkBindMode"
        static let backgroundKeepAlive = "backgroundKeepAlive"
        static let rememberOverlayPosition = "rememberOverlayPosition"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let overlayAppearance = "overlayAppearance"
    }

    #if os(macOS)
    private static let macSettingsMigrationVersion = 1
    private static let macSettingsMigrationVersionDefaultsKey = "macSettingsToICloudMigrationVersion"
    #endif

    // Stored properties so @Observable can track changes.
    // Each syncs to UserDefaults/Keychain on write and loads on init.

    public var voiceEngine: VoiceEngineType {
        didSet {
            UserDefaults.standard.set(voiceEngine.rawValue, forKey: "voiceEngine")
            NSUbiquitousKeyValueStore.default.set(voiceEngine.rawValue, forKey: KVSKey.voiceEngine)
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
            NSUbiquitousKeyValueStore.default.set(openAIVoice, forKey: KVSKey.openAIVoice)
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
            NSUbiquitousKeyValueStore.default.set(elevenLabsVoiceID, forKey: KVSKey.elevenLabsVoiceID)
        }
    }

    public var elevenLabsTurbo: Bool {
        didSet {
            UserDefaults.standard.set(elevenLabsTurbo, forKey: "elevenLabsTurbo")
            NSUbiquitousKeyValueStore.default.set(elevenLabsTurbo, forKey: KVSKey.elevenLabsTurbo)
        }
    }

    public var appleVoiceIdentifier: String? {
        didSet {
            UserDefaults.standard.set(appleVoiceIdentifier, forKey: "appleVoiceIdentifier")
            if let appleVoiceIdentifier {
                NSUbiquitousKeyValueStore.default.set(appleVoiceIdentifier, forKey: KVSKey.appleVoiceIdentifier)
            } else {
                NSUbiquitousKeyValueStore.default.removeObject(forKey: KVSKey.appleVoiceIdentifier)
            }
        }
    }

    public var readingStyle: String {
        didSet {
            UserDefaults.standard.set(readingStyle, forKey: "readingStyle")
            NSUbiquitousKeyValueStore.default.set(readingStyle, forKey: KVSKey.readingStyle)
        }
    }

    public var voiceSpeed: Float {
        didSet {
            UserDefaults.standard.set(voiceSpeed, forKey: "voiceSpeed")
            NSUbiquitousKeyValueStore.default.set(Double(voiceSpeed), forKey: KVSKey.voiceSpeed)
        }
    }

    public var audioOnly: Bool {
        didSet {
            UserDefaults.standard.set(audioOnly, forKey: "audioOnly")
            NSUbiquitousKeyValueStore.default.set(audioOnly, forKey: KVSKey.audioOnly)
        }
    }

    public var pauseOtherAudioDuringSpeech: Bool {
        didSet {
            UserDefaults.standard.set(pauseOtherAudioDuringSpeech, forKey: "pauseOtherAudioDuringSpeech")
            NSUbiquitousKeyValueStore.default.set(pauseOtherAudioDuringSpeech, forKey: KVSKey.pauseOtherAudioDuringSpeech)
        }
    }

    public var networkListenerEnabled: Bool {
        didSet {
            UserDefaults.standard.set(networkListenerEnabled, forKey: "networkListenerEnabled")
            NSUbiquitousKeyValueStore.default.set(networkListenerEnabled, forKey: KVSKey.networkListenerEnabled)
        }
    }

    public var networkListenerPort: UInt16 {
        didSet {
            UserDefaults.standard.set(Int(networkListenerPort), forKey: "networkListenerPort")
            NSUbiquitousKeyValueStore.default.set(Int(networkListenerPort), forKey: KVSKey.networkListenerPort)
        }
    }

    public var networkBindMode: NetworkBindMode {
        didSet {
            UserDefaults.standard.set(networkBindMode.rawValue, forKey: "networkBindMode")
            NSUbiquitousKeyValueStore.default.set(networkBindMode.rawValue, forKey: KVSKey.networkBindMode)
        }
    }

    public var networkAuthToken: String {
        didSet {
            do {
                if networkAuthToken.isEmpty {
                    try KeychainHelper.deleteNetworkAuthToken()
                } else {
                    try KeychainHelper.saveNetworkAuthToken(networkAuthToken)
                }
            } catch {
                Log.settings.error("Failed to persist network auth token: \(error)")
            }
        }
    }

    public var backgroundKeepAlive: Bool {
        didSet {
            UserDefaults.standard.set(backgroundKeepAlive, forKey: "backgroundKeepAlive")
            NSUbiquitousKeyValueStore.default.set(backgroundKeepAlive, forKey: KVSKey.backgroundKeepAlive)
        }
    }

    public var rememberOverlayPosition: Bool {
        didSet {
            UserDefaults.standard.set(rememberOverlayPosition, forKey: "rememberOverlayPosition")
            NSUbiquitousKeyValueStore.default.set(rememberOverlayPosition, forKey: KVSKey.rememberOverlayPosition)
        }
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
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
            NSUbiquitousKeyValueStore.default.set(hasCompletedOnboarding, forKey: KVSKey.hasCompletedOnboarding)
        }
    }

    public var overlayAppearance: OverlayAppearance {
        didSet {
            do {
                let data = try JSONEncoder().encode(overlayAppearance)
                UserDefaults.standard.set(data, forKey: "overlayAppearance")
                NSUbiquitousKeyValueStore.default.set(data, forKey: KVSKey.overlayAppearance)
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
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        if let kvsEngine = kvs.string(forKey: KVSKey.voiceEngine) {
            self.voiceEngine = VoiceEngineType(rawValue: kvsEngine) ?? .apple
        } else {
            self.voiceEngine = VoiceEngineType(rawValue: UserDefaults.standard.string(forKey: "voiceEngine") ?? "apple") ?? .apple
        }

        // App settings should reflect the key explicitly saved in VoxClaw.
        // Avoid env-var override here so stale shell/launchd vars can't shadow Settings.
        let loadedKey = (try? KeychainHelper.readPersistedAPIKey()) ?? ""
        self.openAIAPIKey = loadedKey

        self.openAIVoice = kvs.string(forKey: KVSKey.openAIVoice)
            ?? UserDefaults.standard.string(forKey: "openAIVoice")
            ?? "onyx"

        let loadedElevenLabsKey = (try? KeychainHelper.readPersistedElevenLabsAPIKey()) ?? ""
        self.elevenLabsAPIKey = loadedElevenLabsKey

        self.elevenLabsVoiceID = kvs.string(forKey: KVSKey.elevenLabsVoiceID)
            ?? UserDefaults.standard.string(forKey: "elevenLabsVoiceID")
            ?? "JBFqnCBsd6RMkjVDRZzb"

        if kvs.object(forKey: KVSKey.elevenLabsTurbo) != nil {
            self.elevenLabsTurbo = kvs.bool(forKey: KVSKey.elevenLabsTurbo)
        } else {
            self.elevenLabsTurbo = UserDefaults.standard.bool(forKey: "elevenLabsTurbo")
        }

        if kvs.object(forKey: KVSKey.appleVoiceIdentifier) != nil {
            self.appleVoiceIdentifier = kvs.string(forKey: KVSKey.appleVoiceIdentifier)
        } else {
            self.appleVoiceIdentifier = UserDefaults.standard.string(forKey: "appleVoiceIdentifier")
        }

        self.readingStyle = kvs.string(forKey: KVSKey.readingStyle)
            ?? UserDefaults.standard.string(forKey: "readingStyle")
            ?? ""

        let kvsSpeed = kvs.double(forKey: KVSKey.voiceSpeed)
        let storedSpeed = UserDefaults.standard.float(forKey: "voiceSpeed")
        if kvsSpeed > 0 {
            self.voiceSpeed = Float(kvsSpeed)
        } else {
            self.voiceSpeed = storedSpeed > 0 ? storedSpeed : 1.0
        }

        if kvs.object(forKey: KVSKey.audioOnly) != nil {
            self.audioOnly = kvs.bool(forKey: KVSKey.audioOnly)
        } else {
            self.audioOnly = UserDefaults.standard.bool(forKey: "audioOnly")
        }

        if kvs.object(forKey: KVSKey.pauseOtherAudioDuringSpeech) != nil {
            self.pauseOtherAudioDuringSpeech = kvs.bool(forKey: KVSKey.pauseOtherAudioDuringSpeech)
        } else if UserDefaults.standard.object(forKey: "pauseOtherAudioDuringSpeech") == nil {
            self.pauseOtherAudioDuringSpeech = true
        } else {
            self.pauseOtherAudioDuringSpeech = UserDefaults.standard.bool(forKey: "pauseOtherAudioDuringSpeech")
        }

        if kvs.object(forKey: KVSKey.hasCompletedOnboarding) != nil {
            self.hasCompletedOnboarding = kvs.bool(forKey: KVSKey.hasCompletedOnboarding)
        } else {
            self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        }

        if kvs.object(forKey: KVSKey.networkListenerEnabled) != nil {
            self.networkListenerEnabled = kvs.bool(forKey: KVSKey.networkListenerEnabled)
        } else {
            self.networkListenerEnabled = UserDefaults.standard.bool(forKey: "networkListenerEnabled")
        }

        let storedPort = UserDefaults.standard.integer(forKey: "networkListenerPort")
        let selectedPort: Int
        if kvs.object(forKey: KVSKey.networkListenerPort) != nil {
            selectedPort = Int(kvs.longLong(forKey: KVSKey.networkListenerPort))
        } else {
            selectedPort = storedPort
        }
        self.networkListenerPort = selectedPort > 0 && selectedPort <= Int(UInt16.max) ? UInt16(selectedPort) : 4140

        // Network bind mode (default: localhost for security)
        if let kvsBindMode = kvs.string(forKey: KVSKey.networkBindMode),
           let bindMode = NetworkBindMode(rawValue: kvsBindMode) {
            self.networkBindMode = bindMode
        } else if let storedMode = UserDefaults.standard.string(forKey: "networkBindMode"),
                  let bindMode = NetworkBindMode(rawValue: storedMode) {
            self.networkBindMode = bindMode
        } else {
            self.networkBindMode = .localhost
        }

        // Network auth token (generate if missing)
        if let token = KeychainHelper.readNetworkAuthToken() {
            self.networkAuthToken = token
        } else {
            // Generate a token on first launch
            let generatedToken = (try? KeychainHelper.generateNetworkAuthToken()) ?? ""
            self.networkAuthToken = generatedToken
            Log.settings.info("Generated new network auth token on first launch")
        }

        if kvs.object(forKey: KVSKey.backgroundKeepAlive) != nil {
            self.backgroundKeepAlive = kvs.bool(forKey: KVSKey.backgroundKeepAlive)
        } else if UserDefaults.standard.object(forKey: "backgroundKeepAlive") == nil {
            self.backgroundKeepAlive = true
        } else {
            self.backgroundKeepAlive = UserDefaults.standard.bool(forKey: "backgroundKeepAlive")
        }

        if kvs.object(forKey: KVSKey.rememberOverlayPosition) != nil {
            self.rememberOverlayPosition = kvs.bool(forKey: KVSKey.rememberOverlayPosition)
        } else {
            self.rememberOverlayPosition = UserDefaults.standard.bool(forKey: "rememberOverlayPosition")
        }

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

        if let data = kvs.data(forKey: KVSKey.overlayAppearance),
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

        #if os(macOS)
        migrateCurrentMacSettingsToICloudIfNeeded(kvs: kvs)
        #endif

        observeICloudKVSChanges()
    }

    #if os(macOS)
    /// One-time migration: publish this Mac's current settings to iCloud KVS so iOS/iPadOS
    /// devices can adopt them on upgrade.
    private func migrateCurrentMacSettingsToICloudIfNeeded(kvs: NSUbiquitousKeyValueStore) {
        let currentVersion = UserDefaults.standard.integer(forKey: Self.macSettingsMigrationVersionDefaultsKey)
        guard currentVersion < Self.macSettingsMigrationVersion else { return }

        pushSyncableSettingsToICloud(kvs: kvs)
        UserDefaults.standard.set(Self.macSettingsMigrationVersion, forKey: Self.macSettingsMigrationVersionDefaultsKey)
        Log.settings.info("Migrated current macOS settings to iCloud KVS (v\(Self.macSettingsMigrationVersion, privacy: .public))")
    }
    #endif

    private func pushSyncableSettingsToICloud(kvs: NSUbiquitousKeyValueStore = .default) {
        kvs.set(voiceEngine.rawValue, forKey: KVSKey.voiceEngine)
        kvs.set(openAIVoice, forKey: KVSKey.openAIVoice)
        kvs.set(elevenLabsVoiceID, forKey: KVSKey.elevenLabsVoiceID)
        kvs.set(elevenLabsTurbo, forKey: KVSKey.elevenLabsTurbo)
        if let appleVoiceIdentifier {
            kvs.set(appleVoiceIdentifier, forKey: KVSKey.appleVoiceIdentifier)
        } else {
            kvs.removeObject(forKey: KVSKey.appleVoiceIdentifier)
        }
        kvs.set(readingStyle, forKey: KVSKey.readingStyle)
        kvs.set(Double(voiceSpeed), forKey: KVSKey.voiceSpeed)
        kvs.set(audioOnly, forKey: KVSKey.audioOnly)
        kvs.set(pauseOtherAudioDuringSpeech, forKey: KVSKey.pauseOtherAudioDuringSpeech)
        kvs.set(networkListenerEnabled, forKey: KVSKey.networkListenerEnabled)
        kvs.set(Int(networkListenerPort), forKey: KVSKey.networkListenerPort)
        kvs.set(networkBindMode.rawValue, forKey: KVSKey.networkBindMode)
        kvs.set(backgroundKeepAlive, forKey: KVSKey.backgroundKeepAlive)
        kvs.set(rememberOverlayPosition, forKey: KVSKey.rememberOverlayPosition)
        kvs.set(hasCompletedOnboarding, forKey: KVSKey.hasCompletedOnboarding)
        if let data = try? JSONEncoder().encode(overlayAppearance) {
            kvs.set(data, forKey: KVSKey.overlayAppearance)
        }
        kvs.synchronize()
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

                if changedKeys.contains(KVSKey.voiceEngine),
                   let raw = kvs.string(forKey: KVSKey.voiceEngine),
                   let engine = VoiceEngineType(rawValue: raw),
                   engine != self.voiceEngine {
                    self.voiceEngine = engine
                    Log.settings.info("Voice engine updated from iCloud KVS: \(raw)")
                }

                if changedKeys.contains(KVSKey.openAIVoice),
                   let voice = kvs.string(forKey: KVSKey.openAIVoice),
                   voice != self.openAIVoice {
                    self.openAIVoice = voice
                    Log.settings.info("OpenAI voice updated from iCloud KVS")
                }

                if changedKeys.contains(KVSKey.elevenLabsVoiceID),
                   let voiceID = kvs.string(forKey: KVSKey.elevenLabsVoiceID),
                   voiceID != self.elevenLabsVoiceID {
                    self.elevenLabsVoiceID = voiceID
                    Log.settings.info("ElevenLabs voice updated from iCloud KVS")
                }

                if changedKeys.contains(KVSKey.elevenLabsTurbo) {
                    let turbo = kvs.bool(forKey: KVSKey.elevenLabsTurbo)
                    if turbo != self.elevenLabsTurbo {
                        self.elevenLabsTurbo = turbo
                        Log.settings.info("ElevenLabs turbo updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.appleVoiceIdentifier) {
                    let identifier = kvs.string(forKey: KVSKey.appleVoiceIdentifier)
                    if identifier != self.appleVoiceIdentifier {
                        self.appleVoiceIdentifier = identifier
                        Log.settings.info("Apple voice updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.readingStyle) {
                    let style = kvs.string(forKey: KVSKey.readingStyle) ?? ""
                    if style != self.readingStyle {
                        self.readingStyle = style
                        Log.settings.info("Reading style updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.voiceSpeed) {
                    let speed = Float(kvs.double(forKey: KVSKey.voiceSpeed))
                    if speed > 0, speed != self.voiceSpeed {
                        self.voiceSpeed = speed
                        Log.settings.info("Voice speed updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.audioOnly) {
                    let value = kvs.bool(forKey: KVSKey.audioOnly)
                    if value != self.audioOnly {
                        self.audioOnly = value
                        Log.settings.info("Audio-only setting updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.pauseOtherAudioDuringSpeech) {
                    let value = kvs.object(forKey: KVSKey.pauseOtherAudioDuringSpeech) != nil
                        ? kvs.bool(forKey: KVSKey.pauseOtherAudioDuringSpeech)
                        : true
                    if value != self.pauseOtherAudioDuringSpeech {
                        self.pauseOtherAudioDuringSpeech = value
                        Log.settings.info("Pause-other-audio setting updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.networkListenerEnabled) {
                    let value = kvs.bool(forKey: KVSKey.networkListenerEnabled)
                    if value != self.networkListenerEnabled {
                        self.networkListenerEnabled = value
                        Log.settings.info("Network listener enabled setting updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.networkListenerPort) {
                    let rawPort = Int(kvs.longLong(forKey: KVSKey.networkListenerPort))
                    let port = rawPort > 0 && rawPort <= Int(UInt16.max) ? UInt16(rawPort) : 4140
                    if port != self.networkListenerPort {
                        self.networkListenerPort = port
                        Log.settings.info("Network listener port updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.networkBindMode),
                   let raw = kvs.string(forKey: KVSKey.networkBindMode),
                   let mode = NetworkBindMode(rawValue: raw),
                   mode != self.networkBindMode {
                    self.networkBindMode = mode
                    Log.settings.info("Network bind mode updated from iCloud KVS: \(raw)")
                }

                if changedKeys.contains(KVSKey.backgroundKeepAlive) {
                    let value = kvs.object(forKey: KVSKey.backgroundKeepAlive) != nil
                        ? kvs.bool(forKey: KVSKey.backgroundKeepAlive)
                        : true
                    if value != self.backgroundKeepAlive {
                        self.backgroundKeepAlive = value
                        Log.settings.info("Background keep-alive updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.rememberOverlayPosition) {
                    let value = kvs.bool(forKey: KVSKey.rememberOverlayPosition)
                    if value != self.rememberOverlayPosition {
                        self.rememberOverlayPosition = value
                        Log.settings.info("Remember-overlay-position setting updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.hasCompletedOnboarding) {
                    let value = kvs.bool(forKey: KVSKey.hasCompletedOnboarding)
                    if value != self.hasCompletedOnboarding {
                        self.hasCompletedOnboarding = value
                        Log.settings.info("Onboarding completion updated from iCloud KVS")
                    }
                }

                if changedKeys.contains(KVSKey.overlayAppearance),
                   let data = kvs.data(forKey: KVSKey.overlayAppearance),
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
