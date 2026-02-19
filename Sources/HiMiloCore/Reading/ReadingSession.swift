import Foundation
import os

@MainActor
final class ReadingSession {
    private let appState: AppState
    private let audioPlayer = AudioPlayer()
    private var panelController: PanelController?
    private var keyboardMonitor: KeyboardMonitor?
    private var timings: [WordTiming] = []
    private var displayLink: Timer?

    init(appState: AppState) {
        self.appState = appState
    }

    func start(text: String, voice: String = "onyx") async {
        let wordCount = text.split(separator: " ").count
        let isAudioOnly = appState.audioOnly
        Log.session.info("Session start: \(wordCount, privacy: .public) words, voice=\(voice, privacy: .public), audioOnly=\(isAudioOnly, privacy: .public)")

        appState.sessionState = .loading
        appState.words = text.split(separator: " ").map(String.init)
        appState.currentWordIndex = 0

        // Show panel unless audio-only
        if !appState.audioOnly {
            panelController = PanelController(appState: appState)
            panelController?.show()
        }

        // Start keyboard monitoring
        keyboardMonitor = KeyboardMonitor(session: self)
        keyboardMonitor?.start()

        do {
            let apiKey = try KeychainHelper.readAPIKey()
            let ttsService = TTSService(apiKey: apiKey, voice: voice)

            try audioPlayer.start()
            appState.sessionState = .playing

            // Use heuristic timing until we know real duration
            let heuristicDuration = WordTimingEstimator.heuristicDuration(for: text)
            Log.session.debug("Heuristic duration: \(heuristicDuration, privacy: .public)s")
            timings = WordTimingEstimator.estimate(words: appState.words, totalDuration: heuristicDuration)

            // Start display link for word highlighting
            startDisplayLink()

            // Stream audio chunks
            let stream = await ttsService.streamPCM(text: text)
            for try await chunk in stream {
                audioPlayer.scheduleChunk(chunk)
            }

            // Recalculate timings with actual duration
            let realDuration = audioPlayer.totalDuration
            if realDuration > 0 {
                Log.session.info("Real duration: \(realDuration, privacy: .public)s (heuristic was \(heuristicDuration, privacy: .public)s)")
                timings = WordTimingEstimator.estimate(words: appState.words, totalDuration: realDuration)
            }

            // Schedule completion
            audioPlayer.scheduleEnd { [weak self] in
                Task { @MainActor in
                    self?.finish()
                }
            }

        } catch {
            Log.session.error("Session error: \(error)")
            finish()
        }
    }

    func togglePause() {
        if appState.isPaused {
            Log.session.info("Session resumed")
            audioPlayer.resume()
            appState.isPaused = false
            appState.sessionState = .playing
            startDisplayLink()
            showFeedback("▶ Play")
        } else {
            Log.session.info("Session paused")
            audioPlayer.pause()
            appState.isPaused = true
            appState.sessionState = .paused
            stopDisplayLink()
            showFeedback("⏸ Paused")
        }
    }

    func stop() {
        keyboardMonitor?.stop()
        keyboardMonitor = nil
        audioPlayer.stop()
        finish()
    }

    func skip(seconds: Double) {
        let direction = seconds > 0 ? "→ \(Int(seconds))s" : "← \(Int(abs(seconds)))s"
        showFeedback(direction)
    }

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateWordHighlight()
            }
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateWordHighlight() {
        guard appState.sessionState == .playing else { return }
        let currentTime = audioPlayer.currentTime
        let index = WordTimingEstimator.wordIndex(at: currentTime, in: timings)
        if index != appState.currentWordIndex {
            appState.currentWordIndex = index
        }
    }

    private func finish() {
        Log.session.info("Session finished")
        stopDisplayLink()
        keyboardMonitor?.stop()
        keyboardMonitor = nil
        appState.sessionState = .finished

        // Auto-dismiss after 0.5s
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
