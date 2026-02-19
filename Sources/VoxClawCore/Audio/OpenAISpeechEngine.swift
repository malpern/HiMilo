import Foundation
import os

@MainActor
final class OpenAISpeechEngine: SpeechEngine {
    weak var delegate: SpeechEngineDelegate?
    private(set) var state: SpeechEngineState = .idle

    private let apiKey: String
    private let voice: String
    private let audioPlayer = AudioPlayer()
    private var timings: [WordTiming] = []
    private var words: [String] = []
    private var displayLink: Timer?

    init(apiKey: String, voice: String = "onyx") {
        self.apiKey = apiKey
        self.voice = voice
    }

    func start(text: String, words: [String]) async {
        self.words = words
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        do {
            let ttsService = TTSService(apiKey: apiKey, voice: voice)
            try audioPlayer.start()

            state = .playing
            delegate?.speechEngine(self, didChangeState: .playing)

            // Heuristic timing until real duration known
            let heuristicDuration = WordTimingEstimator.heuristicDuration(for: text)
            timings = WordTimingEstimator.estimate(words: words, totalDuration: heuristicDuration)
            startDisplayLink()

            // Stream audio
            let stream = await ttsService.streamPCM(text: text)
            for try await chunk in stream {
                audioPlayer.scheduleChunk(chunk)
            }

            // Recalculate with real duration
            let realDuration = audioPlayer.totalDuration
            if realDuration > 0 {
                Log.tts.info("Real duration: \(realDuration, privacy: .public)s (heuristic was \(heuristicDuration, privacy: .public)s)")
                timings = WordTimingEstimator.estimate(words: words, totalDuration: realDuration)
            }

            // Detect completion
            audioPlayer.scheduleEnd { [weak self] in
                Task { @MainActor in
                    self?.handleFinished()
                }
            }
        } catch {
            Log.tts.error("OpenAI engine error: \(error)")
            state = .error(error.localizedDescription)
            delegate?.speechEngine(self, didEncounterError: error)
        }
    }

    func pause() {
        audioPlayer.pause()
        stopDisplayLink()
        state = .paused
        delegate?.speechEngine(self, didChangeState: .paused)
    }

    func resume() {
        audioPlayer.resume()
        startDisplayLink()
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    func stop() {
        stopDisplayLink()
        audioPlayer.stop()
        state = .idle
        delegate?.speechEngine(self, didChangeState: .idle)
    }

    // MARK: - Display link for word tracking

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
        guard case .playing = state else { return }
        let currentTime = audioPlayer.currentTime
        let index = WordTimingEstimator.wordIndex(at: currentTime, in: timings)
        delegate?.speechEngine(self, didUpdateWordIndex: index)
    }

    private func handleFinished() {
        stopDisplayLink()
        state = .finished
        delegate?.speechEngineDidFinish(self)
    }
}
