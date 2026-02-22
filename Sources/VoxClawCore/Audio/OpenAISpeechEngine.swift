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
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        do {
            let player = try AudioPlayer()
            self.audioPlayer = player
            let ttsService = TTSService(apiKey: apiKey, voice: voice, speed: speed, instructions: instructions)
            try player.start()

            state = .playing
            delegate?.speechEngine(self, didChangeState: .playing)

            // Heuristic timing until real duration known
            let heuristicDuration = WordTimingEstimator.heuristicDuration(for: text)
            timings = WordTimingEstimator.estimate(words: words, totalDuration: heuristicDuration)
            startDisplayLink()

            // Stream audio, feeding chunks to both player and speech aligner
            let aligner = SpeechAligner(words: words)
            let stream = await ttsService.streamPCM(text: text)
            for try await chunk in stream {
                player.scheduleChunk(chunk)
                aligner?.appendChunk(chunk)
            }
            aligner?.finishAudio()

            // Use recognizer timings if available, otherwise fall back to heuristic
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
