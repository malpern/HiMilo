import Foundation
import os

@MainActor
public final class OpenAISpeechEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    public private(set) var state: SpeechEngineState = .idle

    private let apiKey: String
    private let voice: String
    private let speed: Float
    private let instructions: String?
    private var originalSpeed: Float = 1.0
    private var audioPlayer: AudioPlayer?
    private var cadenceTimings: [WordTiming] = []
    private var finalTimings: [WordTiming]?
    private var aligner: SpeechAligner?
    private var words: [String] = []
    private var displayLink: Timer?
    private var playbackStartTime: ContinuousClock.Instant?
    private var loggedAlignerSwitch = false
    private var streamComplete = false
    private var finalTimingsSource: TimingSource = .cadence

    public init(apiKey: String, voice: String = "onyx", speed: Float = 1.0, instructions: String? = nil) {
        self.apiKey = apiKey
        self.voice = voice
        self.speed = speed
        self.instructions = instructions
    }

    public func start(text: String, words: [String]) async {
        self.words = words
        self.originalSpeed = speed
        self.finalTimings = nil
        self.loggedAlignerSwitch = false
        self.playbackStartTime = nil
        self.streamComplete = false
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        // Cadence timings for immediate highlighting before aligner catches up.
        cadenceTimings = WordTimingEstimator.estimateCadence(words: words, rate: speed)

        do {
            let player = try AudioPlayer()
            self.audioPlayer = player
            let ttsService = TTSService(apiKey: apiKey, voice: voice, speed: speed, instructions: instructions)
            try player.prepare()

            let prebufferCount = 5
            let aligner = SpeechAligner(words: words)
            self.aligner = aligner
            let stream = await ttsService.streamPCM(text: text)
            var chunksBuffered = 0

            for try await chunk in stream {
                player.scheduleChunk(chunk)
                aligner?.appendChunk(chunk)
                chunksBuffered += 1

                if chunksBuffered == prebufferCount {
                    player.play()
                    playbackStartTime = .now
                    state = .playing
                    delegate?.speechEngine(self, didChangeState: .playing)
                    startDisplayLink()
                }
            }

            if chunksBuffered < prebufferCount {
                player.play()
                playbackStartTime = .now
                state = .playing
                delegate?.speechEngine(self, didChangeState: .playing)
                startDisplayLink()
            }
            streamComplete = true
            aligner?.finishAudio()

            // Stream is done — immediately set proportional timings based on known duration.
            // This replaces the cadence heuristic even before aligner finishes.
            let realDuration = player.totalDuration
            if realDuration > 0 {
                let proportionalTimings = WordTimingEstimator.estimate(words: words, totalDuration: realDuration)
                if finalTimings == nil {
                    finalTimings = proportionalTimings
                    finalTimingsSource = .proportional
                    Log.tts.info("Set proportional timings from stream duration (\(realDuration, privacy: .public)s)")
                }
            }
            // If aligner is available, wait for aligned timings to upgrade the estimate.
            if let aligner, aligner.isAvailable {
                await aligner.awaitCompletion(timeout: 3.0)
                let alignedTimings = aligner.timings
                if !alignedTimings.isEmpty {
                    Log.tts.info("Upgraded to aligned timings: \(alignedTimings.count) words")
                    finalTimings = alignedTimings
                    finalTimingsSource = .aligned
                }
            }

            player.scheduleEnd { [weak self] in
                Task { @MainActor in
                    self?.handleFinished()
                }
            }
        } catch {
            handleEngineError(error)
        }
    }

    public func pause() {
        audioPlayer?.pause()
        stopDisplayLink()
        state = .paused
        delegate?.speechEngine(self, didChangeState: .paused)
    }

    public func resume() {
        audioPlayer?.resume()
        startDisplayLink()
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    public func stop() {
        stopDisplayLink()
        audioPlayer?.stop()
        aligner = nil
        state = .idle
        delegate?.speechEngine(self, didChangeState: .idle)
    }

    public func setSpeed(_ speed: Float) {
        guard originalSpeed > 0 else { return }
        audioPlayer?.playbackRate = speed / originalSpeed
    }

    // MARK: - Display link for word tracking

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateWordHighlight()
            }
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private var lastReportedTimingSource: TimingSource?

    private func updateWordHighlight() {
        guard case .playing = state else { return }
        let currentTime = audioPlayer?.currentTime ?? 0

        // Priority: final timings > progressive aligner timings > cadence heuristic
        let activeTimings: [WordTiming]
        let source: TimingSource
        if let final = finalTimings {
            source = finalTimingsSource
            activeTimings = final
        } else if let partial = aligner?.timings, !partial.isEmpty {
            if !loggedAlignerSwitch, let start = playbackStartTime {
                let elapsed = ContinuousClock.now - start
                let elapsedMs = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
                Log.tts.info("⏱ Switched to aligner timings after \(elapsedMs)ms of playback (\(partial.count) words)")
                loggedAlignerSwitch = true
            }
            source = .aligner
            activeTimings = partial
        } else {
            source = .cadence
            activeTimings = cadenceTimings
        }

        if source != lastReportedTimingSource {
            lastReportedTimingSource = source
            delegate?.speechEngine(self, didChangeTimingSource: source)
        }

        let index = WordTimingEstimator.wordIndex(at: currentTime, in: activeTimings)
        delegate?.speechEngine(self, didUpdateWordIndex: index)
    }

    private func handleFinished() {
        stopDisplayLink()
        aligner = nil
        state = .finished
        delegate?.speechEngineDidFinish(self)
    }

    func handleEngineError(_ error: Error) {
        if let ttsError = error as? TTSService.TTSError, ttsError.statusCode == 401 {
            NotificationCenter.default.post(
                name: .voxClawOpenAIAuthFailed,
                object: nil,
                userInfo: [VoxClawNotificationUserInfo.openAIAuthErrorMessage: ttsError.message]
            )
        }
        Log.tts.error("OpenAI engine error: \(error)")
        state = .error(error.localizedDescription)
        delegate?.speechEngine(self, didEncounterError: error)
    }
}
