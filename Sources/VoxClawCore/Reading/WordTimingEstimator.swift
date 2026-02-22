import Foundation

struct WordTiming: Sendable {
    let word: String
    let startTime: Double
    let endTime: Double
}

enum WordTimingEstimator {
    static func estimate(words: [String], totalDuration: Double) -> [WordTiming] {
        guard !words.isEmpty, totalDuration > 0 else { return [] }

        // Calculate relative weights for each word
        var weights: [Double] = []
        for (index, word) in words.enumerated() {
            var weight = Double(word.count)

            // Add punctuation pauses
            if let lastChar = word.last {
                switch lastChar {
                case ".", "!", "?":
                    weight += 6.0 // sentence boundary pause
                case ",", ";", ":":
                    weight += 3.0 // clause boundary pause
                default:
                    break
                }
            }

            // Add paragraph break pause (detect by checking if word ends with newline-like patterns)
            if index < words.count - 1 {
                let nextWord = words[index + 1]
                if nextWord.hasPrefix("\n") || nextWord.hasPrefix("\r") {
                    weight += 6.0 // ~500ms pause equivalent
                }
            }

            weights.append(weight)
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return [] }

        // Convert weights to timings
        var timings: [WordTiming] = []
        var currentTime: Double = 0

        for (index, word) in words.enumerated() {
            let duration = (weights[index] / totalWeight) * totalDuration
            let timing = WordTiming(
                word: word,
                startTime: currentTime,
                endTime: currentTime + duration
            )
            timings.append(timing)
            currentTime += duration
        }

        return timings
    }

    static func wordIndex(at time: Double, in timings: [WordTiming]) -> Int {
        guard !timings.isEmpty else { return 0 }

        // Binary search for the word at the given time
        var low = 0
        var high = timings.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let timing = timings[mid]

            if time < timing.startTime {
                high = mid - 1
            } else if time >= timing.endTime {
                low = mid + 1
            } else {
                return mid
            }
        }

        // Clamp to valid range
        return min(max(low, 0), timings.count - 1)
    }

    static func heuristicDuration(for text: String) -> Double {
        // Rough estimate: ~150ms per character for speech
        return Double(text.count) * 0.015
    }

    /// Per-word cadence estimate for immediate highlighting before real timings are available.
    /// Tuned to match typical OpenAI TTS timing (~150 wpm at 1x, ~60ms/char).
    static func estimateCadence(words: [String], rate: Float) -> [WordTiming] {
        guard !words.isEmpty else { return [] }

        let basePerChar: Double = 0.075 / Double(max(rate, 0.5)) // ~75ms per char at 1x
        let minWordDuration: Double = 0.18 / Double(max(rate, 0.5))

        var timings: [WordTiming] = []
        var currentTime: Double = 0

        for word in words {
            var duration = max(Double(word.count) * basePerChar, minWordDuration)

            // Punctuation pauses
            if let lastChar = word.last {
                switch lastChar {
                case ".", "!", "?":
                    duration += 0.45 / Double(max(rate, 0.5))
                case ",", ";", ":":
                    duration += 0.20 / Double(max(rate, 0.5))
                default:
                    break
                }
            }

            timings.append(WordTiming(word: word, startTime: currentTime, endTime: currentTime + duration))
            currentTime += duration
        }

        return timings
    }
}
