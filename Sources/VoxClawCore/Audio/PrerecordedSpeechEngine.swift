#if os(macOS)
import AVFoundation
import Foundation
import os

@MainActor
final class PrerecordedSpeechEngine: NSObject, SpeechEngine {
    weak var delegate: SpeechEngineDelegate?
    private(set) var state: SpeechEngineState = .idle

    private let audioURL: URL
    private var player: AVAudioPlayer?
    private var words: [String] = []
    private var timings: [WordTiming] = []
    private var displayLink: Timer?
    private var playbackStart: ContinuousClock.Instant?

    init(audioURL: URL) {
        self.audioURL = audioURL
    }

    private static let log = Logger(subsystem: "com.malpern.voxclaw", category: "prerecorded")

    func start(text: String, words: [String]) async {
        self.words = words
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        do {
            let p = try AVAudioPlayer(contentsOf: audioURL)
            p.delegate = self
            p.prepareToPlay()
            self.player = p

            timings = WordTimingEstimator.estimate(words: words, totalDuration: p.duration)

            let started = p.play()
            Self.log.info("AVAudioPlayer.play() returned \(started), duration=\(p.duration)")
            playbackStart = .now
            state = .playing
            delegate?.speechEngine(self, didChangeState: .playing)
            startDisplayLink()
        } catch {
            Self.log.error("PrerecordedSpeechEngine failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            delegate?.speechEngine(self, didEncounterError: error)
            delegate?.speechEngineDidFinish(self)
        }
    }

    func pause() {
        player?.pause()
        stopDisplayLink()
        state = .paused
        delegate?.speechEngine(self, didChangeState: .paused)
    }

    func resume() {
        player?.play()
        startDisplayLink()
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    func stop() {
        stopDisplayLink()
        player?.stop()
        player = nil
        state = .idle
        delegate?.speechEngine(self, didChangeState: .idle)
    }

    func setSpeed(_ speed: Float) {
        player?.rate = speed
    }

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
        guard let start = playbackStart, let player else { return }
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        var currentIndex = 0
        for (i, timing) in timings.enumerated() {
            if seconds >= timing.startTime {
                currentIndex = i
            }
        }
        delegate?.speechEngine(self, didUpdateWordIndex: currentIndex)
    }

    private func handleFinished() {
        stopDisplayLink()
        if let lastIndex = words.indices.last {
            delegate?.speechEngine(self, didUpdateWordIndex: lastIndex)
        }
        state = .finished
        delegate?.speechEngine(self, didChangeState: .finished)
        delegate?.speechEngineDidFinish(self)
    }
}

extension PrerecordedSpeechEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.handleFinished()
        }
    }
}
#endif
