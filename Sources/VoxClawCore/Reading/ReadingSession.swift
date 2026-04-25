import Foundation
import SwiftUI
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
    private var pausedExternalPlayback: PlaybackSnapshot?
    private var isFinalized = false
    private var finishTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var speedIndicatorTask: Task<Void, Never>?
    private var didAttemptExternalPause = false
    private var isBlockerPaused = false
    private var finishContinuation: CheckedContinuation<Void, Never>?
    /// Optional callback invoked when the user requests stop (e.g. via the overlay's
    /// stop button). When set, this is called instead of `stop()` so the coordinator
    /// can also clear any queued speech. If nil, the panel calls `stop()` directly.
    public var onUserStop: (@MainActor () -> Void)?
    /// When true, finish clears content but keeps the panel visible so the
    /// coordinator can do a smooth transition to the next queued item.
    public var keepPanelOnFinish = false
    #if os(macOS)
    private let externalPanelController: PanelController?
    #endif

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
        #if os(macOS)
        self.externalPanelController = nil
        #endif
        engine.delegate = self
    }

    #if os(macOS)
    init(
        appState: AppState,
        engine: any SpeechEngine,
        settings: SettingsManager? = nil,
        pauseExternalAudioDuringSpeech: Bool = false,
        playbackController: any ExternalPlaybackControlling = ExternalPlaybackController(),
        externalPanelController: PanelController?
    ) {
        self.appState = appState
        self.engine = engine
        self.settings = settings
        self.pauseExternalAudioDuringSpeech = pauseExternalAudioDuringSpeech
        self.playbackController = playbackController
        self.externalPanelController = externalPanelController
        engine.delegate = self
    }
    #endif

    private static let sessionTimeout: Duration = .seconds(300)

    /// Suspends until this session is fully stopped or finished, with a hard
    /// timeout to prevent a hung TTS stream from zombifying the queue.
    public func waitUntilFinished() async {
        if isFinalized { return }

        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.sessionTimeout)
            guard let self, !self.isFinalized else { return }
            Log.session.warning("Session timed out after \(Int(Self.sessionTimeout.components.seconds), privacy: .public)s — force-stopping")
            self.stop()
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if isFinalized {
                cont.resume()
            } else {
                finishContinuation = cont
            }
        }

        timeoutTask.cancel()
    }

    private func resumeFinishContinuationIfNeeded() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    public var hasFinished: Bool { isFinalized }

    public func dismissPanel() {
        #if os(macOS)
        panelController?.dismissInstantly()
        panelController = nil
        #endif
    }

    /// Pause initiated by the coordinator because a blocker (mic / defer-list app)
    /// became active mid-speech. Distinguished from the user-pause button only
    /// in logging — both share the same engine pause path and visual state.
    public func pauseForBlocker() {
        guard !isFinalized, !appState.isPaused else { return }
        isBlockerPaused = true
        Log.session.info("pauseForBlocker: engine.pause()")
        engine.pause()
        appState.isPaused = true
        appState.sessionState = .paused
    }

    public func resumeFromBlocker() {
        let blockerFlag = isBlockerPaused
        let userPaused = appState.isPaused
        guard !isFinalized, userPaused, blockerFlag else {
            Log.session.info("resumeFromBlocker: skipping (blockerPaused=\(blockerFlag, privacy: .public), userPaused=\(userPaused, privacy: .public))")
            return
        }
        isBlockerPaused = false
        Log.session.info("resumeFromBlocker: engine.resume()")
        engine.resume()
        appState.isPaused = false
        appState.sessionState = .playing
    }

    public func start(text: String) async {
        isFinalized = false
        didAttemptExternalPause = false
        pausedExternalPlayback = nil
        finishTask?.cancel()
        finishTask = nil

        let words = Self.splitPreservingParagraphs(text)
        let isAudioOnly = appState.audioOnly
        let wordCount = words.count
        let preview = String(text.prefix(80))
        Log.session.info("Session.start: \(wordCount, privacy: .public) words, audioOnly=\(isAudioOnly, privacy: .public), text=\"\(preview, privacy: .public)\"")

        appState.sessionState = .loading
        appState.words = words
        appState.currentWordIndex = 0
        let wordsSet = appState.words.count
        Log.session.info("Session.start: appState.words.count=\(wordsSet, privacy: .public)")

        // Prepare panel but don't show yet — audio leads, visuals follow.
        #if os(macOS)
        if !appState.audioOnly {
            if let external = externalPanelController {
                panelController = external
                Log.panel.info("Session.start: reusing external panel")
            } else {
                let effectiveSettings = settings ?? SettingsManager()
                panelController = PanelController(appState: appState, settings: effectiveSettings, onTogglePause: { [weak self] in
                    self?.togglePause()
                }, onStop: { [weak self] in
                    guard let self else { return }
                    if let onUserStop = self.onUserStop {
                        onUserStop()
                    } else {
                        self.stop()
                    }
                })
                Log.panel.info("Session.start: panel prepared, will show when audio begins")
            }
        } else {
            Log.panel.info("Session.start: skipping panel (audioOnly=true)")
        }
        #endif

        if pauseExternalAudioDuringSpeech {
            didAttemptExternalPause = true
            pausedExternalPlayback = playbackController.pauseIfPlaying()
            if pausedExternalPlayback != nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let currentSpeed = settings?.voiceSpeed ?? 1.0
        if currentSpeed != 1.0 {
            showSpeedIndicator(currentSpeed)
        }

        Log.session.info("Session.start: calling engine.start")
        assert(!pauseExternalAudioDuringSpeech || didAttemptExternalPause, "External playback pause must run before engine.start")
        await engine.start(text: text, words: words)
        Log.session.info("Session.start: engine.start returned")
    }

    public func togglePause() {
        if appState.isPaused {
            Log.session.info("Session resumed (manual)")
            isBlockerPaused = false
            engine.resume()
            appState.isPaused = false
            appState.sessionState = .playing
        } else {
            Log.session.info("Session paused (manual)")
            isBlockerPaused = false
            engine.pause()
            appState.isPaused = true
            appState.sessionState = .paused
        }
    }

    public func stop() {
        engine.stop()
        speedIndicatorTask?.cancel()
        finish(mutatingAppState: true, delayedReset: false)
    }

    public func setSpeed(_ speed: Float) {
        engine.setSpeed(speed)
        showSpeedIndicator(speed)
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
        speedIndicatorTask?.cancel()
        #if os(macOS)
        panelController?.dismiss()
        panelController = nil
        #endif
        isFinalized = true
        resumeFinishContinuationIfNeeded()
        resumeExternalPlaybackIfNeeded()
    }

    // MARK: - SpeechEngineDelegate

    public func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int) {
        if index != appState.currentWordIndex {
            appState.currentWordIndex = index
        }
    }

    public func speechEngine(_ engine: any SpeechEngine, didChangeTimingSource source: TimingSource) {
        appState.timingSource = source
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
            #if os(macOS)
            panelController?.show()
            #endif
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
        resumeExternalPlaybackIfNeeded()

        if delayedReset && mutatingAppState {
            #if os(macOS)
            let hasExternalPanel = externalPanelController != nil
            #else
            let hasExternalPanel = false
            #endif
            let keepFlag = keepPanelOnFinish
            let shouldKeepPanel = keepFlag || hasExternalPanel
            if shouldKeepPanel {
                Log.session.info("finish: keeping panel (keepOnFinish=\(keepFlag, privacy: .public), external=\(hasExternalPanel, privacy: .public))")
                appState.sessionState = .finished
                finishTask = Task { @MainActor [weak self] in
                    // Fade out old content
                    withAnimation(.easeOut(duration: 0.3)) {
                        self?.appState.contentFadedOut = true
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                    self?.appState.words = []
                    self?.appState.currentWordIndex = 0
                    self?.appState.contentFadedOut = false
                    self?.appState.sessionState = .idle
                    self?.resumeFinishContinuationIfNeeded()
                }
            } else {
                Log.session.info("finish: scheduling delayed reset (500ms)")
                finishTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        Log.session.info("finish: delayed reset cancelled during sleep")
                        self?.resumeFinishContinuationIfNeeded()
                        return
                    }
                    if Task.isCancelled {
                        Log.session.info("finish: delayed reset cancelled after sleep")
                        self?.resumeFinishContinuationIfNeeded()
                        return
                    }
                    Log.session.info("finish: delayed reset firing — dismissing panel and resetting appState")
                    #if os(macOS)
                    self?.panelController?.dismiss()
                    #endif
                    self?.appState.reset()
                    let wc = self?.appState.words.count ?? -1
                    Log.session.info("finish: delayed reset complete, words=\(wc, privacy: .public)")
                    self?.resumeFinishContinuationIfNeeded()
                }
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
            resumeFinishContinuationIfNeeded()
        }
    }

    private func showSpeedIndicator(_ speed: Float) {
        let text = String(format: "%.1fx", speed)
        appState.speedIndicatorText = text
        speedIndicatorTask?.cancel()
        speedIndicatorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(3250))
            if self?.appState.speedIndicatorText == text {
                self?.appState.speedIndicatorText = nil
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

    /// Unicode paragraph separator used as a sentinel in the words array to
    /// create visual gaps between paragraphs in the overlay panel.
    public static let paragraphSentinel = "\u{2029}"

    static func splitPreservingParagraphs(_ text: String) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var words: [String] = []
        for (i, para) in paragraphs.enumerated() {
            if i > 0 && !words.isEmpty {
                words.append(paragraphSentinel)
            }
            let paraWords = para.split(whereSeparator: \.isWhitespace).map(String.init)
            words.append(contentsOf: paraWords)
        }
        return words
    }

    private func resumeExternalPlaybackIfNeeded() {
        guard let snapshot = pausedExternalPlayback else { return }
        assert(!snapshot.isEmpty, "Stored playback snapshots must contain at least one paused target")
        playbackController.resume(snapshot)
        pausedExternalPlayback = nil
    }
}
