import Foundation
import os

@MainActor
final class ReadingSession: SpeechEngineDelegate {
    private let appState: AppState
    private let engine: any SpeechEngine
    private var panelController: PanelController?

    init(appState: AppState, engine: any SpeechEngine) {
        self.appState = appState
        self.engine = engine
        engine.delegate = self
    }

    func start(text: String) async {
        let words = text.split(separator: " ").map(String.init)
        let isAudioOnly = appState.audioOnly
        Log.session.info("Session start: \(words.count, privacy: .public) words, audioOnly=\(isAudioOnly, privacy: .public)")

        appState.sessionState = .loading
        appState.words = words
        appState.currentWordIndex = 0

        // Show panel unless audio-only
        if !appState.audioOnly {
            panelController = PanelController(appState: appState)
            panelController?.show()
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
        finish()
    }

    // MARK: - SpeechEngineDelegate

    func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int) {
        if index != appState.currentWordIndex {
            appState.currentWordIndex = index
        }
    }

    func speechEngineDidFinish(_ engine: any SpeechEngine) {
        finish()
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
        finish()
    }

    // MARK: - Private

    private func finish() {
        Log.session.info("Session finished")
        appState.sessionState = .finished

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            panelController?.dismiss()
            appState.reset()
        }
    }

    private func showFeedback(_ text: String) {
        appState.feedbackText = text
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if appState.feedbackText == text {
                appState.feedbackText = nil
            }
        }
    }
}
