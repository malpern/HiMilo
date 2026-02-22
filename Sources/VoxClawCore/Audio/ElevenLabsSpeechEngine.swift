import Foundation
import os

@MainActor
public final class ElevenLabsSpeechEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    public private(set) var state: SpeechEngineState = .idle

    private let apiKey: String
    private let voiceID: String
    private let speed: Float
    private let turbo: Bool
    private var originalSpeed: Float = 1.0
    private var audioPlayer: AudioPlayer?
    private var cadenceTimings: [WordTiming] = []
    private var finalTimings: [WordTiming]?
    private var words: [String] = []
    private var displayLink: Timer?
    private var playbackStartTime: ContinuousClock.Instant?
    private var streamComplete = false

    public init(apiKey: String, voiceID: String, speed: Float = 1.0, turbo: Bool = false) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.speed = speed
        self.turbo = turbo
    }

    public func start(text: String, words: [String]) async {
        self.words = words
        self.originalSpeed = speed
        self.finalTimings = nil
        self.playbackStartTime = nil
        self.streamComplete = false
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        // Cadence timings as initial fallback before server timestamps arrive
        cadenceTimings = WordTimingEstimator.estimateCadence(words: words, rate: speed)

        do {
            let player = try AudioPlayer()
            self.audioPlayer = player
            let ttsService = ElevenLabsTTSService(apiKey: apiKey, voiceID: voiceID, speed: speed, turbo: turbo)
            try player.prepare()

            let prebufferCount = 5
            let stream = await ttsService.streamWithTimestamps(text: text)
            var chunksBuffered = 0
            var accumulatedAlignments: [ElevenLabsAlignment] = []

            for try await chunk in stream {
                player.scheduleChunk(chunk.audio)
                chunksBuffered += 1

                if let alignment = chunk.alignment {
                    accumulatedAlignments.append(alignment)
                    // Convert accumulated alignments to word timings as they arrive
                    let wordTimings = Self.convertAlignmentsToWordTimings(
                        accumulatedAlignments, words: words
                    )
                    if !wordTimings.isEmpty {
                        finalTimings = wordTimings
                    }
                }

                if chunksBuffered == prebufferCount {
                    player.play()
                    playbackStartTime = .now
                    state = .playing
                    delegate?.speechEngine(self, didChangeState: .playing)
                    delegate?.speechEngine(self, didChangeTimingSource: finalTimings != nil ? .aligned : .cadence)
                    startDisplayLink()
                }
            }

            if chunksBuffered < prebufferCount {
                player.play()
                playbackStartTime = .now
                state = .playing
                delegate?.speechEngine(self, didChangeState: .playing)
                delegate?.speechEngine(self, didChangeTimingSource: finalTimings != nil ? .aligned : .cadence)
                startDisplayLink()
            }
            streamComplete = true

            // Final timing conversion after all chunks received
            if !accumulatedAlignments.isEmpty {
                let wordTimings = Self.convertAlignmentsToWordTimings(
                    accumulatedAlignments, words: words
                )
                if !wordTimings.isEmpty {
                    finalTimings = wordTimings
                    delegate?.speechEngine(self, didChangeTimingSource: .aligned)
                    Log.tts.info("ElevenLabs final aligned timings: \(wordTimings.count) words")
                }
            }

            // If no alignment data came back, fall back to proportional timings
            if finalTimings == nil {
                let realDuration = player.totalDuration
                if realDuration > 0 {
                    finalTimings = WordTimingEstimator.estimate(words: words, totalDuration: realDuration)
                    delegate?.speechEngine(self, didChangeTimingSource: .proportional)
                    Log.tts.info("ElevenLabs: no alignment data, using proportional timings")
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

        let activeTimings: [WordTiming]
        let source: TimingSource
        if let final = finalTimings {
            source = .aligned
            activeTimings = final
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
        state = .finished
        delegate?.speechEngineDidFinish(self)
    }

    func handleEngineError(_ error: Error) {
        if let ttsError = error as? ElevenLabsTTSService.TTSError, ttsError.statusCode == 401 {
            NotificationCenter.default.post(
                name: .voxClawElevenLabsAuthFailed,
                object: nil,
                userInfo: [VoxClawNotificationUserInfo.elevenLabsAuthErrorMessage: ttsError.message]
            )
        }
        Log.tts.error("ElevenLabs engine error: \(error)")
        state = .error(error.localizedDescription)
        delegate?.speechEngine(self, didEncounterError: error)
    }

    // MARK: - Alignment conversion

    /// Convert ElevenLabs character-level timestamps to word-level WordTimings.
    /// Maps character positions from the alignment data back to word boundaries in the original text.
    static func convertAlignmentsToWordTimings(
        _ alignments: [ElevenLabsAlignment],
        words: [String]
    ) -> [WordTiming] {
        guard !alignments.isEmpty, !words.isEmpty else { return [] }

        // Flatten all alignment data into a single character timeline
        var allCharStartMs: [Int] = []
        var allCharDurationMs: [Int] = []
        var allChars: [String] = []

        for alignment in alignments {
            let count = min(alignment.charStartTimesMs.count, alignment.charDurationsMs.count, alignment.chars.count)
            for i in 0..<count {
                allCharStartMs.append(alignment.charStartTimesMs[i])
                allCharDurationMs.append(alignment.charDurationsMs[i])
                allChars.append(alignment.chars[i])
            }
        }

        guard !allChars.isEmpty else { return [] }

        // Build the full text from alignment chars to find word boundaries
        let alignedText = allChars.joined()

        // Map each word to its character range in the aligned text
        var timings: [WordTiming] = []
        var searchStart = alignedText.startIndex

        for word in words {
            // Find the word in the aligned text starting from our current position
            guard let range = alignedText.range(of: word, range: searchStart..<alignedText.endIndex) else {
                // Word not found — skip spaces and try to find next word-like characters
                // Use the last known timing to avoid gaps
                if let lastTiming = timings.last {
                    timings.append(WordTiming(
                        word: word,
                        startTime: lastTiming.endTime,
                        endTime: lastTiming.endTime + 0.1
                    ))
                }
                continue
            }

            let charStartIndex = alignedText.distance(from: alignedText.startIndex, to: range.lowerBound)
            let charEndIndex = alignedText.distance(from: alignedText.startIndex, to: range.upperBound) - 1

            guard charStartIndex < allCharStartMs.count else { break }

            let startTimeMs = allCharStartMs[charStartIndex]
            let endCharIdx = min(charEndIndex, allCharStartMs.count - 1)
            let endTimeMs = allCharStartMs[endCharIdx] + allCharDurationMs[endCharIdx]

            timings.append(WordTiming(
                word: word,
                startTime: Double(startTimeMs) / 1000.0,
                endTime: Double(endTimeMs) / 1000.0
            ))

            searchStart = range.upperBound
        }

        return timings
    }
}
