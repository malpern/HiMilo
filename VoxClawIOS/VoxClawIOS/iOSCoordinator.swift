import AVFoundation
import SwiftUI
import UIKit
import VoxClawCore

@Observable
@MainActor
final class iOSCoordinator: SpeechQueueDelegate {
    private var networkListener: VoxClawCore.NetworkListener?
    private var interruptionTask: Task<Void, Never>?
    let queue = SpeechQueueCoordinator()
    let keepAlive = BackgroundAudioKeepAlive()
    let peerBrowser = PeerBrowser()

    func startListening(appState: AppState, settings: SettingsManager) {
        stopListening()
        queue.delegate = self
        peerBrowser.start()
        let port = settings.networkListenerPort
        let listener = VoxClawCore.NetworkListener(port: port, appState: appState, settings: settings)
        do {
            try listener.start(
                onReadRequest: { [weak self] request in
                    await MainActor.run {
                        guard let self else { return }
                        self.keepAlive.resetTimeout()
                        self.configureAudioSession()
                        UIApplication.shared.isIdleTimerDisabled = true
                        self.queue.enqueue(
                            request.text,
                            appState: appState,
                            settings: settings,
                            projectId: request.projectId
                        )
                    }
                },
                onAck: { [weak self] projectId in
                    await MainActor.run {
                        self?.queue.handleAck(projectId: projectId, appState: appState)
                    }
                },
                onControl: { [weak self] control in
                    await MainActor.run {
                        self?.queue.handleControl(control, deviceID: "ios-\(UIDevice.current.name)")
                    }
                }
            )
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
        configureAudioSession()
        UIApplication.shared.isIdleTimerDisabled = true
        queue.enqueue(text, appState: appState, settings: settings)
    }

    func togglePause() {
        queue.togglePause()
    }

    func stop() {
        queue.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private let deviceID = "ios-\(UIDevice.current.name)"

    // MARK: - SpeechQueueDelegate

    func makeEngine(for item: SpeechQueueCoordinator.QueueItem, settings: SettingsManager) async -> (any SpeechEngine)? {
        guard item.engineOverride == nil else { return item.engineOverride }
        return settings.createEngine()
    }

    func onControlAction(_ action: HTTPRequestParser.ControlAction) {
        let relayIDs = SettingsManager().relayPeerIDs
        guard !relayIDs.isEmpty else { return }
        for peer in peerBrowser.peers {
            guard relayIDs.contains(peer.id), let baseURL = peer.baseURL else { continue }
            guard let url = URL(string: "\(baseURL)/control") else { continue }
            let payload: [String: Any] = ["action": action.rawValue, "origin": deviceID]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 2
            let request = req
            Task.detached { _ = try? await URLSession.shared.data(for: request) }
        }
    }

    // MARK: - Background / Interruptions

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
                    if self.queue.activeSession != nil, !appState.isPaused {
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
