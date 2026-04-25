import Foundation
import os

/// A `SpeechEngine` that produces no audio but drives the same word-by-word
/// highlighting on the overlay using `WordTimingEstimator.estimateCadence`.
/// Used when `AudioActivityMonitor` reports a defer-list app is still busy
/// after the polite-wait window expires.
@MainActor
public final class SilentSpeechEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    public private(set) var state: SpeechEngineState = .idle

    private let rate: Float
    private var words: [String] = []
    private var timings: [WordTiming] = []
    private var startInstant: ContinuousClock.Instant?
    private var pausedAtElapsed: Duration?
    private var tickTask: Task<Void, Never>?
    private var currentRate: Float

    public init(rate: Float = 1.0) {
        self.rate = rate
        self.currentRate = rate
    }

    public func start(text: String, words: [String]) async {
        self.words = words
        self.timings = WordTimingEstimator.estimateCadence(words: words, rate: currentRate)
        self.startInstant = .now
        self.pausedAtElapsed = nil
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        Log.tts.info("SilentSpeech starting: \(words.count, privacy: .public) words")

        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
        startTicking()
    }

    public func pause() {
        guard case .playing = state, let start = startInstant else { return }
        pausedAtElapsed = ContinuousClock.now - start
        tickTask?.cancel()
        tickTask = nil
        state = .paused
        delegate?.speechEngine(self, didChangeState: .paused)
    }

    public func resume() {
        guard case .paused = state, let pausedElapsed = pausedAtElapsed else { return }
        startInstant = ContinuousClock.now - pausedElapsed
        pausedAtElapsed = nil
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
        startTicking()
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        state = .idle
        delegate?.speechEngine(self, didChangeState: .idle)
    }

    public func setSpeed(_ speed: Float) {
        // Recompute timings at new rate, preserving current word position.
        let oldIndex = currentWordIndex()
        currentRate = speed
        timings = WordTimingEstimator.estimateCadence(words: words, rate: speed)
        if oldIndex < timings.count {
            startInstant = ContinuousClock.now - .seconds(timings[oldIndex].startTime)
        }
    }

    private func currentWordIndex() -> Int {
        guard let start = startInstant else { return 0 }
        let elapsed = (pausedAtElapsed ?? (ContinuousClock.now - start))
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return WordTimingEstimator.wordIndex(at: seconds, in: timings)
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            var lastIndex = -1
            while !Task.isCancelled {
                guard let self else { return }
                guard case .playing = self.state else { return }
                guard let start = self.startInstant else { return }
                let elapsed = ContinuousClock.now - start
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

                let totalDuration = self.timings.last?.endTime ?? 0
                if seconds >= totalDuration {
                    self.delegate?.speechEngine(self, didUpdateWordIndex: max(0, self.words.count - 1))
                    self.state = .finished
                    self.delegate?.speechEngine(self, didChangeState: .finished)
                    self.delegate?.speechEngineDidFinish(self)
                    return
                }

                let idx = WordTimingEstimator.wordIndex(at: seconds, in: self.timings)
                if idx != lastIndex {
                    lastIndex = idx
                    self.delegate?.speechEngine(self, didUpdateWordIndex: idx)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
