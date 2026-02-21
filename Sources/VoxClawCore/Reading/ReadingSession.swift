import Foundation
import os

@MainActor
final class ReadingSession: SpeechEngineDelegate {
    private let appState: AppState
    private let engine: any SpeechEngine
    private let pauseExternalAudioDuringSpeech: Bool
    private let playbackController: any ExternalPlaybackControlling
    private var panelController: PanelController?
    private var pausedExternalAudio = false
    private var isFinalized = false
    private var finishTask: Task<Void, Never>?

    init(
        appState: AppState,
        engine: any SpeechEngine,
        pauseExternalAudioDuringSpeech: Bool = false,
        playbackController: any ExternalPlaybackControlling = ExternalPlaybackController()
    ) {
        self.appState = appState
        self.engine = engine
        self.pauseExternalAudioDuringSpeech = pauseExternalAudioDuringSpeech
        self.playbackController = playbackController
        engine.delegate = self
    }

    func start(text: String) async {
        isFinalized = false
        finishTask?.cancel()
        finishTask = nil

        let words = text.split(separator: " ").map(String.init)
        let isAudioOnly = appState.audioOnly
        Log.session.info("Session start: \(words.count, privacy: .public) words, audioOnly=\(isAudioOnly, privacy: .public)")

        appState.sessionState = .loading
        appState.words = words
        appState.currentWordIndex = 0

        // Show panel unless audio-only
        if !appState.audioOnly {
            panelController = PanelController(appState: appState, onTogglePause: { [weak self] in
                self?.togglePause()
            })
            panelController?.show()
        }

        if pauseExternalAudioDuringSpeech {
            pausedExternalAudio = playbackController.pauseIfPlaying()
        }

        await engine.start(text: text, words: words)
    }

    func togglePause() {
        if appState.isPaused {
            Log.session.info("Session resumed")
            engine.resume()
            appState.isPaused = false
            appState.sessionState = .playing
            showFeedback("▶ Play")
        } else {
            Log.session.info("Session paused")
            engine.pause()
            appState.isPaused = true
            appState.sessionState = .paused
            showFeedback("⏸ Paused")
        }
    }

    func stop() {
        engine.stop()
        finish(mutatingAppState: true, delayedReset: false)
    }

    /// Stop this session because a new one is replacing it.
    /// Do not mutate shared app state, otherwise stale callbacks can clear the new session UI.
    func stopForReplacement() {
        engine.stop()
        finish(mutatingAppState: false, delayedReset: false)
    }

    // MARK: - SpeechEngineDelegate

    func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int) {
        if index != appState.currentWordIndex {
            appState.currentWordIndex = index
        }
    }

    func speechEngineDidFinish(_ engine: any SpeechEngine) {
        finish(mutatingAppState: true, delayedReset: true)
    }

    func speechEngine(_ engine: any SpeechEngine, didChangeState state: SpeechEngineState) {
        switch state {
        case .playing:
            appState.sessionState = .playing
        case .loading:
            appState.sessionState = .loading
        case .paused:
            appState.sessionState = .paused
        case .finished, .idle, .error:
            break
        }
    }

    func speechEngine(_ engine: any SpeechEngine, didEncounterError error: Error) {
        Log.session.error("Engine error: \(error)")
        finish(mutatingAppState: true, delayedReset: true)
    }

    // MARK: - Private

    private func finish(mutatingAppState: Bool, delayedReset: Bool) {
        // Always cancel any pending delayed reset first, even if this session
        // was already finalized, to prevent stale tasks from clearing a newer session.
        finishTask?.cancel()
        finishTask = nil

        guard !isFinalized else { return }
        isFinalized = true

        Log.session.info("Session finished")
        if mutatingAppState {
            appState.sessionState = .finished
        }
        if pausedExternalAudio {
            playbackController.resumePaused()
            pausedExternalAudio = false
        }

        if delayedReset && mutatingAppState {
            finishTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                if Task.isCancelled {
                    return
                }
                self?.panelController?.dismiss()
                self?.appState.reset()
            }
        } else {
            panelController?.dismiss()
            if mutatingAppState {
                appState.reset()
            }
        }
    }

    private func showFeedback(_ text: String) {
        appState.feedbackText = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if self?.appState.feedbackText == text {
                self?.appState.feedbackText = nil
            }
        }
    }
}
