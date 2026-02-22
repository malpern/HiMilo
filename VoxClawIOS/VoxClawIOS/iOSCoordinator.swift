import AVFoundation
import SwiftUI
import UIKit
import VoxClawCore

@Observable
@MainActor
final class iOSCoordinator {
    private var networkListener: VoxClawCore.NetworkListener?
    private var activeSession: ReadingSession?
    private var interruptionTask: Task<Void, Never>?
    let keepAlive = BackgroundAudioKeepAlive()

    func startListening(appState: AppState, settings: SettingsManager) {
        stopListening()
        let port = settings.networkListenerPort
        let listener = VoxClawCore.NetworkListener(port: port, appState: appState)
        do {
            try listener.start { [weak self] request in
                await self?.handleReadRequest(request, appState: appState, settings: settings)
            }
            self.networkListener = listener
        } catch {
            print("Failed to start listener: \(error)")
        }
    }

    func stopListening() {
        networkListener?.stop()
        networkListener = nil
    }

    func readText(_ text: String, appState: AppState, settings: SettingsManager) async {
        keepAlive.resetTimeout()
        activeSession?.stopForReplacement()
        appState.audioOnly = false

        configureAudioSession()
        UIApplication.shared.isIdleTimerDisabled = true

        let engine = settings.createEngine()
        let session = ReadingSession(
            appState: appState,
            engine: engine,
            settings: settings,
            pauseExternalAudioDuringSpeech: false
        )
        activeSession = session
        await session.start(text: text)

        UIApplication.shared.isIdleTimerDisabled = false
    }

    func togglePause() {
        activeSession?.togglePause()
    }

    func stop() {
        activeSession?.stop()
        activeSession = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func handleReadRequest(_ request: ReadRequest, appState: AppState, settings: SettingsManager) async {
        keepAlive.resetTimeout()
        let voice = request.voice ?? settings.openAIVoice
        let rate = request.rate ?? 1.0
        let instructions = request.instructions ?? (settings.readingStyle.isEmpty ? nil : settings.readingStyle)
        var engine: (any SpeechEngine)?
        if !settings.openAIAPIKey.isEmpty {
            let primary = OpenAISpeechEngine(apiKey: settings.openAIAPIKey, voice: voice, speed: rate, instructions: instructions)
            let fallback = AppleSpeechEngine(voiceIdentifier: settings.appleVoiceIdentifier, rate: rate)
            engine = FallbackSpeechEngine(primary: primary, fallback: fallback)
        } else if request.rate != nil {
            engine = AppleSpeechEngine(rate: rate)
        }

        activeSession?.stopForReplacement()
        appState.audioOnly = false

        configureAudioSession()
        UIApplication.shared.isIdleTimerDisabled = true

        let finalEngine = engine ?? settings.createEngine()
        let session = ReadingSession(
            appState: appState,
            engine: finalEngine,
            settings: settings,
            pauseExternalAudioDuringSpeech: false
        )
        activeSession = session
        await session.start(text: request.text)

        UIApplication.shared.isIdleTimerDisabled = false
    }

    func enterBackground(settings: SettingsManager) {
        guard settings.backgroundKeepAlive else { return }
        configureAudioSession()
        keepAlive.start()
    }

    func exitBackground() {
        keepAlive.stop()
    }

    func observeAudioInterruptions(appState: AppState) {
        interruptionTask?.cancel()
        interruptionTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                guard let self else { return }
                guard let info = notification.userInfo,
                      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { continue }

                if type == .began {
                    if self.activeSession != nil, !appState.isPaused {
                        self.togglePause()
                    }
                }
            }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }
    }
}
