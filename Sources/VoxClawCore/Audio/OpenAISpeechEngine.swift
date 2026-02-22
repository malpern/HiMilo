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
    private var timings: [WordTiming] = []
    private var words: [String] = []
    private var displayLink: Timer?

    public init(apiKey: String, voice: String = "onyx", speed: Float = 1.0, instructions: String? = nil) {
        self.apiKey = apiKey
        self.voice = voice
        self.speed = speed
        self.instructions = instructions
    }

    public func start(text: String, words: [String]) async {
        self.words = words
        self.originalSpeed = speed
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        do {
            let player = try AudioPlayer()
            self.audioPlayer = player
            let ttsService = TTSService(apiKey: apiKey, voice: voice, speed: speed, instructions: instructions)
            try player.prepare()

            // Buffer initial chunks before starting playback to prevent stutter.
            // Each chunk is ~100ms (4800 bytes), so 5 chunks ≈ 500ms of lead-in.
            let prebufferCount = 5
            let aligner = SpeechAligner(words: words)
            let stream = await ttsService.streamPCM(text: text)
            var chunksBuffered = 0

            for try await chunk in stream {
                player.scheduleChunk(chunk)
                aligner?.appendChunk(chunk)
                chunksBuffered += 1

                if chunksBuffered == prebufferCount {
                    player.play()
                    state = .playing
                    delegate?.speechEngine(self, didChangeState: .playing)
                }
            }

            // Short text may finish before prebuffer threshold — start if not yet playing.
            if chunksBuffered < prebufferCount {
                player.play()
                state = .playing
                delegate?.speechEngine(self, didChangeState: .playing)
            }
            aligner?.finishAudio()

            // Compute accurate timings now that the full duration is known,
            // then start the display link. This avoids the highlight racing
            // ahead when heuristic timings underestimate the real duration.
            let realDuration = player.totalDuration
            if let aligner, aligner.isAvailable {
                await aligner.awaitCompletion(timeout: 3.0)
                let alignedTimings = aligner.timings
                if !alignedTimings.isEmpty {
                    Log.tts.info("Using speech-aligned timings (\(alignedTimings.count) words)")
                    timings = alignedTimings
                } else if realDuration > 0 {
                    Log.tts.info("Aligner produced no timings, falling back to heuristic (duration: \(realDuration, privacy: .public)s)")
                    timings = WordTimingEstimator.estimate(words: words, totalDuration: realDuration)
                }
            } else if realDuration > 0 {
                Log.tts.info("Speech aligner unavailable, using heuristic (duration: \(realDuration, privacy: .public)s)")
                timings = WordTimingEstimator.estimate(words: words, totalDuration: realDuration)
            }
            startDisplayLink()

            // Detect completion
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

    private func updateWordHighlight() {
        guard case .playing = state else { return }
        let currentTime = audioPlayer?.currentTime ?? 0
        let index = WordTimingEstimator.wordIndex(at: currentTime, in: timings)
        delegate?.speechEngine(self, didUpdateWordIndex: index)
    }

    private func handleFinished() {
        stopDisplayLink()
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
