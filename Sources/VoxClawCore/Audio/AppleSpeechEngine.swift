import AVFoundation
import os

@MainActor
public final class AppleSpeechEngine: NSObject, SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    public private(set) var state: SpeechEngineState = .idle

    private let synthesizer = AVSpeechSynthesizer()
    private var words: [String] = []
    private let voiceIdentifier: String?
    private var rate: Float
    private var currentWordIndex: Int = 0
    private var wordIndexOffset: Int = 0

    /// Maps character offset ranges in the original text to word indices.
    private var charOffsetToWordIndex: [(range: Range<Int>, wordIndex: Int)] = []

    public init(voiceIdentifier: String? = nil, rate: Float = 1.0) {
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
        super.init()
        synthesizer.delegate = self
    }

    public func start(text: String, words: [String]) async {
        self.words = words
        self.currentWordIndex = 0
        self.wordIndexOffset = 0
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)

        // Build character-offset-to-word-index map
        charOffsetToWordIndex = Self.buildCharMap(text: text, words: words)

        let utterance = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        let targetRate = AVSpeechUtteranceDefaultSpeechRate * rate
        utterance.rate = min(max(targetRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)

        Log.tts.info("Apple speech starting with voice: \(utterance.voice?.name ?? "default", privacy: .public)")

        synthesizer.speak(utterance)
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    public func pause() {
        synthesizer.pauseSpeaking(at: .word)
        state = .paused
        delegate?.speechEngine(self, didChangeState: .paused)
    }

    public func resume() {
        synthesizer.continueSpeaking()
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        delegate?.speechEngine(self, didChangeState: .idle)
    }

    public func setSpeed(_ speed: Float) {
        self.rate = speed
        switch state {
        case .playing, .paused: break
        default: return
        }
        let resumeIndex = currentWordIndex
        synthesizer.stopSpeaking(at: .immediate)
        let remainingWords = Array(words[resumeIndex...])
        guard !remainingWords.isEmpty else { return }
        let remainingText = remainingWords.joined(separator: " ")
        // Track offset so delegate callbacks map back to original word indices
        wordIndexOffset = resumeIndex
        charOffsetToWordIndex = Self.buildCharMap(text: remainingText, words: remainingWords)
        let utterance = AVSpeechUtterance(string: remainingText)
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        let targetRate = AVSpeechUtteranceDefaultSpeechRate * speed
        utterance.rate = min(max(targetRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        synthesizer.speak(utterance)
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    // MARK: - Character range to word index mapping

    /// Walk the text, recording the character range for each word.
    static func buildCharMap(text: String, words: [String]) -> [(range: Range<Int>, wordIndex: Int)] {
        var result: [(range: Range<Int>, wordIndex: Int)] = []
        var searchStart = text.startIndex

        for (index, word) in words.enumerated() {
            guard let range = text.range(of: word, range: searchStart..<text.endIndex) else {
                continue
            }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            result.append((range: start..<end, wordIndex: index))
            searchStart = range.upperBound
        }
        return result
    }

    /// Given a character offset from the willSpeak delegate callback, find the word index.
    func wordIndex(forCharacterOffset offset: Int) -> Int? {
        for entry in charOffsetToWordIndex {
            if entry.range.contains(offset) {
                return entry.wordIndex
            }
        }
        return nil
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AppleSpeechEngine: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let offset = characterRange.location
        Task { @MainActor in
            if let idx = self.wordIndex(forCharacterOffset: offset) {
                let adjustedIdx = idx + self.wordIndexOffset
                self.currentWordIndex = adjustedIdx
                self.delegate?.speechEngine(self, didUpdateWordIndex: adjustedIdx)
            }
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .finished
            self.delegate?.speechEngineDidFinish(self)
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .paused
            self.delegate?.speechEngine(self, didChangeState: .paused)
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .playing
            self.delegate?.speechEngine(self, didChangeState: .playing)
        }
    }
}
