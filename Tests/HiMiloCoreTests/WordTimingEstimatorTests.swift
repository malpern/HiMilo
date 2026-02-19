@testable import HiMiloCore
import Testing

struct WordTimingEstimatorTests {
    // MARK: - estimate(words:totalDuration:)

    @Test func estimateEmptyWords() {
        let result = WordTimingEstimator.estimate(words: [], totalDuration: 5.0)
        #expect(result.isEmpty)
    }

    @Test func estimateZeroDuration() {
        let result = WordTimingEstimator.estimate(words: ["hello"], totalDuration: 0)
        #expect(result.isEmpty)
    }

    @Test func estimateSingleWord() {
        let result = WordTimingEstimator.estimate(words: ["hello"], totalDuration: 1.0)
        #expect(result.count == 1)
        #expect(result[0].word == "hello")
        #expect(result[0].startTime == 0)
        #expect(abs(result[0].endTime - 1.0) < 0.001)
    }

    @Test func estimateMultipleWordsSpanFullDuration() {
        let words = ["hello", "world"]
        let result = WordTimingEstimator.estimate(words: words, totalDuration: 10.0)
        #expect(result.count == 2)
        #expect(result[0].startTime == 0)
        #expect(abs(result.last!.endTime - 10.0) < 0.001)
        // Timings are contiguous
        #expect(abs(result[0].endTime - result[1].startTime) < 0.001)
    }

    @Test func estimateTimingsAreContiguous() {
        let words = ["the", "quick", "brown", "fox", "jumps"]
        let result = WordTimingEstimator.estimate(words: words, totalDuration: 5.0)
        #expect(result.count == 5)
        for i in 0..<(result.count - 1) {
            #expect(abs(result[i].endTime - result[i + 1].startTime) < 0.001)
        }
    }

    @Test func estimateLongerWordsGetMoreTime() {
        let words = ["hi", "extraordinary"]
        let result = WordTimingEstimator.estimate(words: words, totalDuration: 10.0)
        let shortDuration = result[0].endTime - result[0].startTime
        let longDuration = result[1].endTime - result[1].startTime
        #expect(longDuration > shortDuration)
    }

    @Test func estimatePeriodAddsWeight() {
        let twoPlain = WordTimingEstimator.estimate(words: ["test", "word"], totalDuration: 10.0)
        let twoPeriod = WordTimingEstimator.estimate(words: ["test", "word."], totalDuration: 10.0)
        let plainDur = twoPlain[1].endTime - twoPlain[1].startTime
        let periodDur = twoPeriod[1].endTime - twoPeriod[1].startTime
        #expect(periodDur > plainDur)
    }

    @Test func estimatePeriodGetsMoreWeightThanComma() {
        let twoComma = WordTimingEstimator.estimate(words: ["test", "word,"], totalDuration: 10.0)
        let twoPeriod = WordTimingEstimator.estimate(words: ["test", "word."], totalDuration: 10.0)
        let commaDur = twoComma[1].endTime - twoComma[1].startTime
        let periodDur = twoPeriod[1].endTime - twoPeriod[1].startTime
        #expect(periodDur > commaDur)
    }

    @Test func estimateNegativeDuration() {
        let result = WordTimingEstimator.estimate(words: ["hello"], totalDuration: -1.0)
        #expect(result.isEmpty)
    }

    // MARK: - wordIndex(at:in:)

    @Test func wordIndexEmptyTimings() {
        let index = WordTimingEstimator.wordIndex(at: 1.0, in: [])
        #expect(index == 0)
    }

    @Test func wordIndexFindsCorrectWord() {
        let timings = [
            WordTiming(word: "hello", startTime: 0, endTime: 1.0),
            WordTiming(word: "world", startTime: 1.0, endTime: 2.0),
            WordTiming(word: "test", startTime: 2.0, endTime: 3.0),
        ]
        #expect(WordTimingEstimator.wordIndex(at: 0.5, in: timings) == 0)
        #expect(WordTimingEstimator.wordIndex(at: 1.5, in: timings) == 1)
        #expect(WordTimingEstimator.wordIndex(at: 2.5, in: timings) == 2)
    }

    @Test func wordIndexAtBoundary() {
        let timings = [
            WordTiming(word: "a", startTime: 0, endTime: 1.0),
            WordTiming(word: "b", startTime: 1.0, endTime: 2.0),
        ]
        // At exactly 1.0, endTime of first word → should advance to second
        #expect(WordTimingEstimator.wordIndex(at: 1.0, in: timings) == 1)
    }

    @Test func wordIndexPastEnd() {
        let timings = [
            WordTiming(word: "a", startTime: 0, endTime: 1.0),
        ]
        #expect(WordTimingEstimator.wordIndex(at: 5.0, in: timings) == 0)
    }

    @Test func wordIndexBeforeStart() {
        let timings = [
            WordTiming(word: "a", startTime: 1.0, endTime: 2.0),
        ]
        #expect(WordTimingEstimator.wordIndex(at: 0.0, in: timings) == 0)
    }

    // MARK: - heuristicDuration(for:)

    @Test func heuristicDurationEmptyString() {
        #expect(WordTimingEstimator.heuristicDuration(for: "") == 0)
    }

    @Test func heuristicDurationScalesWithLength() {
        let short = WordTimingEstimator.heuristicDuration(for: "hi")
        let long = WordTimingEstimator.heuristicDuration(for: "hello world this is longer")
        #expect(long > short)
    }

    @Test func heuristicDurationFormula() {
        // 0.015 * character count
        let result = WordTimingEstimator.heuristicDuration(for: "hello")
        #expect(abs(result - 0.075) < 0.0001)
    }
}
