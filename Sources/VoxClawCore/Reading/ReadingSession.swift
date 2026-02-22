import Foundation
import os

@MainActor
public final class ReadingSession: SpeechEngineDelegate {
    private let appState: AppState
    private let engine: any SpeechEngine
    private let settings: SettingsManager?
    private let pauseExternalAudioDuringSpeech: Bool
    private let playbackController: any ExternalPlaybackControlling
    #if os(macOS)
    private var panelController: PanelController?
    #endif
    private var pausedExternalAudio = false
    private var isFinalized = false
    private var finishTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    public init(
        appState: AppState,
        engine: any SpeechEngine,
        settings: SettingsManager? = nil,
        pauseExternalAudioDuringSpeech: Bool = false,
        playbackController: any ExternalPlaybackControlling = ExternalPlaybackController()
    ) {
        self.appState = appState
        self.engine = engine
        self.settings = settings
        self.pauseExternalAudioDuringSpeech = pauseExternalAudioDuringSpeech
        self.playbackController = playbackController
        engine.delegate = self
    }

    public func start(text: String) async {
        isFinalized = false
        finishTask?.cancel()
        finishTask = nil

        let words = text.split(separator: " ").map(String.init)
        let isAudioOnly = appState.audioOnly
        let wordCount = words.count
        let preview = String(text.prefix(80))
        Log.session.info("Session.start: \(wordCount, privacy: .public) words, audioOnly=\(isAudioOnly, privacy: .public), text=\"\(preview, privacy: .public)\"")

        appState.sessionState = .loading
        appState.words = words
        appState.currentWordIndex = 0
        let wordsSet = appState.words.count
        Log.session.info("Session.start: appState.words.count=\(wordsSet, privacy: .public)")

        // Show panel unless audio-only
        #if os(macOS)
        if !appState.audioOnly {
            let effectiveSettings = settings ?? SettingsManager()
            panelController = PanelController(appState: appState, settings: effectiveSettings, onTogglePause: { [weak self] in
                self?.togglePause()
            }, onStop: { [weak self] in
                self?.stop()
            })
            Log.panel.info("Session.start: calling panelController.show()")
            panelController?.show()
        } else {
            Log.panel.info("Session.start: skipping panel (audioOnly=true)")
        }
        #endif

        if pauseExternalAudioDuringSpeech {
            pausedExternalAudio = playbackController.pauseIfPlaying()
        }

        Log.session.info("Session.start: calling engine.start")
        await engine.start(text: text, words: words)
        Log.session.info("Session.start: engine.start returned")
    }

    public func togglePause() {
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

    public func stop() {
        engine.stop()
        finish(mutatingAppState: true, delayedReset: false)
    }

    public func setSpeed(_ speed: Float) {
        engine.setSpeed(speed)
    }

    /// Stop this session because a new one is replacing it.
    /// Do not mutate shared app state, otherwise stale callbacks can clear the new session UI.
    public func stopForReplacement() {
        let finalized = isFinalized
        let hadFinishTask = finishTask != nil
        #if os(macOS)
        let hadPanel = panelController != nil
        #else
        let hadPanel = false
        #endif
        Log.session.info("stopForReplacement: isFinalized=\(finalized, privacy: .public), hadFinishTask=\(hadFinishTask, privacy: .public), hadPanel=\(hadPanel, privacy: .public)")
        engine.stop()
        finishTask?.cancel()
        finishTask = nil
        #if os(macOS)
        panelController?.dismiss()
        panelController = nil
        #endif
        isFinalized = true
        if pausedExternalAudio {
            playbackController.resumePaused()
            pausedExternalAudio = false
        }
    }

    // MARK: - SpeechEngineDelegate

    public func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int) {
        if index != appState.currentWordIndex {
            appState.currentWordIndex = index
        }
    }

    public func speechEngineDidFinish(_ engine: any SpeechEngine) {
        let finalized = isFinalized
        Log.session.info("speechEngineDidFinish: isFinalized=\(finalized, privacy: .public)")
        finish(mutatingAppState: true, delayedReset: true)
    }

    public func speechEngine(_ engine: any SpeechEngine, didChangeState state: SpeechEngineState) {
        let desc = String(describing: state)
        Log.session.info("Engine state → \(desc, privacy: .public)")
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

    public func speechEngine(_ engine: any SpeechEngine, didEncounterError error: Error) {
        Log.session.error("Engine error: \(error)")
        finish(mutatingAppState: true, delayedReset: true)
    }

    // MARK: - Private

    private func finish(mutatingAppState: Bool, delayedReset: Bool) {
        let finalized = isFinalized
        let hadFinishTask = finishTask != nil
        Log.session.info("finish: mutating=\(mutatingAppState, privacy: .public), delayed=\(delayedReset, privacy: .public), isFinalized=\(finalized, privacy: .public), hadFinishTask=\(hadFinishTask, privacy: .public)")
        finishTask?.cancel()
        finishTask = nil

        guard !isFinalized else {
            Log.session.info("finish: already finalized, returning early")
            return
        }
        isFinalized = true

        if mutatingAppState {
            appState.sessionState = .finished
        }
        if pausedExternalAudio {
            playbackController.resumePaused()
            pausedExternalAudio = false
        }

        if delayedReset && mutatingAppState {
            Log.session.info("finish: scheduling delayed reset (500ms)")
            finishTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    Log.session.info("finish: delayed reset cancelled during sleep")
                    return
                }
                if Task.isCancelled {
                    Log.session.info("finish: delayed reset cancelled after sleep")
                    return
                }
                Log.session.info("finish: delayed reset firing — dismissing panel and resetting appState")
                #if os(macOS)
                self?.panelController?.dismiss()
                #endif
                self?.appState.reset()
                let wc = self?.appState.words.count ?? -1
                Log.session.info("finish: delayed reset complete, words=\(wc, privacy: .public)")
            }
        } else {
            Log.session.info("finish: immediate cleanup, dismissing panel")
            #if os(macOS)
            panelController?.dismiss()
            #endif
            if mutatingAppState {
                appState.reset()
                let wc = appState.words.count
                Log.session.info("finish: appState reset, words=\(wc, privacy: .public)")
            }
        }
    }

    private func showFeedback(_ text: String) {
        appState.feedbackText = text
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if self?.appState.feedbackText == text {
                self?.appState.feedbackText = nil
            }
        }
    }
}
