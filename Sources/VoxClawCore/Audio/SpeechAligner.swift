import AVFoundation
import Foundation
import Speech
import Synchronization
import os

/// Uses on-device `SFSpeechRecognizer` to align recognized words with the original
/// word array, producing accurate per-word timestamps from OpenAI TTS audio.
///
/// Audio buffers (16-bit PCM, 24kHz mono) are fed directly to a speech recognition
/// request — no microphone is used. Falls back gracefully when recognition is
/// unavailable or the user denies permission.
///
/// Marked `@unchecked Sendable` because `SFSpeechRecognizer`,
/// `SFSpeechAudioBufferRecognitionRequest`, and `SFSpeechRecognitionTask` are not
/// Sendable. Mutable state (`_timings`, `_isFinished`) is protected by a `Mutex`.
final class SpeechAligner: @unchecked Sendable {
    private let words: [String]
    private let recognizer: SFSpeechRecognizer?
    private let recognitionRequest: SFSpeechAudioBufferRecognitionRequest
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioFormat: AVAudioFormat

    private let _timings = Mutex<[WordTiming]>([])
    private let _isFinished = Mutex(false)

    /// Progressively updated word timings from speech recognition.
    var timings: [WordTiming] {
        _timings.withLock { $0 }
    }

    /// Whether speech recognition is available and authorized.
    var isAvailable: Bool {
        guard let recognizer else { return false }
        return recognizer.isAvailable
    }

    init?(words: [String]) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        ) else {
            Log.tts.error("Failed to create audio format for speech alignment")
            return nil
        }

        self.words = words
        self.audioFormat = format

        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest.shouldReportPartialResults = true
        self.recognitionRequest.requiresOnDeviceRecognition = true
        // addsPunctuation defaults to true which helps matching
        self.recognitionRequest.addsPunctuation = true

        startRecognition()
    }

    /// Feed a 16-bit signed LE PCM chunk (24kHz mono) to the recognizer.
    func appendChunk(_ pcmData: Data) {
        guard let buffer = AudioPlayer.pcmBuffer(from: pcmData, format: audioFormat) else { return }
        recognitionRequest.append(buffer)
    }

    /// Signal that all audio has been provided.
    func finishAudio() {
        recognitionRequest.endAudio()
    }

    /// Wait until recognition produces a final result or times out.
    func awaitCompletion(timeout: TimeInterval = 5.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !_isFinished.withLock({ $0 }) {
            if Date() >= deadline { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Private

    private func startRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            Log.tts.info("Speech recognizer not available, will use heuristic timings")
            _isFinished.withLock { $0 = true }
            return
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let aligned = self.align(transcription: result.bestTranscription)
                self._timings.withLock { $0 = aligned }

                if result.isFinal {
                    Log.tts.info("Speech alignment complete: \(aligned.count) words aligned")
                    self._isFinished.withLock { $0 = true }
                }
            }

            if let error {
                Log.tts.warning("Speech recognition error: \(error.localizedDescription)")
                self._isFinished.withLock { $0 = true }
            }
        }
    }

    /// Map recognized segments back to the original word array using greedy matching.
    private func align(transcription: SFTranscription) -> [WordTiming] {
        let segments = transcription.segments
        guard !segments.isEmpty, !words.isEmpty else { return [] }

        // Build anchor points: map each recognized segment to a word in the original array
        var anchors: [(wordIndex: Int, startTime: Double, endTime: Double)] = []
        var cursor = 0

        for segment in segments {
            let recognized = Self.normalize(segment.substring)
            guard !recognized.isEmpty else { continue }

            // Search forward from cursor for a match
            for i in cursor..<words.count {
                let original = Self.normalize(words[i])
                if original == recognized {
                    anchors.append((
                        wordIndex: i,
                        startTime: segment.timestamp,
                        endTime: segment.timestamp + segment.duration
                    ))
                    cursor = i + 1
                    break
                }
            }
        }

        guard !anchors.isEmpty else { return [] }

        // Build full timings array, interpolating gaps between anchors
        var result = [WordTiming]()
        result.reserveCapacity(words.count)

        // Handle words before the first anchor
        if anchors[0].wordIndex > 0 {
            let gapCount = anchors[0].wordIndex
            let gapDuration = anchors[0].startTime / Double(gapCount)
            for i in 0..<gapCount {
                result.append(WordTiming(
                    word: words[i],
                    startTime: Double(i) * gapDuration,
                    endTime: Double(i + 1) * gapDuration
                ))
            }
        }

        // Process anchors and gaps between them
        for anchorIdx in 0..<anchors.count {
            let anchor = anchors[anchorIdx]

            // Fill gap between previous anchor and this one
            if anchorIdx > 0 {
                let prevAnchor = anchors[anchorIdx - 1]
                let gapStart = prevAnchor.wordIndex + 1
                let gapEnd = anchor.wordIndex
                let gapCount = gapEnd - gapStart

                if gapCount > 0 {
                    let gapTimeStart = prevAnchor.endTime
                    let gapTimeEnd = anchor.startTime
                    let gapDuration = (gapTimeEnd - gapTimeStart) / Double(gapCount)

                    for i in 0..<gapCount {
                        let wordIdx = gapStart + i
                        result.append(WordTiming(
                            word: words[wordIdx],
                            startTime: gapTimeStart + Double(i) * gapDuration,
                            endTime: gapTimeStart + Double(i + 1) * gapDuration
                        ))
                    }
                }
            }

            // Add the anchor word itself
            result.append(WordTiming(
                word: words[anchor.wordIndex],
                startTime: anchor.startTime,
                endTime: anchor.endTime
            ))
        }

        // Handle words after the last anchor by extrapolating
        guard let lastAnchor = anchors.last else { return result }
        let remainingStart = lastAnchor.wordIndex + 1
        if remainingStart < words.count {
            // Estimate duration per remaining word from average anchor duration
            let avgDuration = anchors.map { $0.endTime - $0.startTime }
                .reduce(0, +) / Double(anchors.count)
            let perWord = max(avgDuration, 0.1)
            var t = lastAnchor.endTime

            for i in remainingStart..<words.count {
                result.append(WordTiming(
                    word: words[i],
                    startTime: t,
                    endTime: t + perWord
                ))
                t += perWord
            }
        }

        return result
    }

    /// Normalize a word for comparison: lowercase, strip punctuation.
    static func normalize(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
