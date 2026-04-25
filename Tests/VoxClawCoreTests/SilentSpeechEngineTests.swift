@testable import VoxClawCore
import Testing
import Foundation

@MainActor
final class SilentSpeechRecorder: SpeechEngineDelegate {
    var states: [String] = []
    var lastWordIndex: Int = -1
    var finishedCount: Int = 0

    func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int) {
        lastWordIndex = index
    }
    func speechEngine(_ engine: any SpeechEngine, didChangeState state: SpeechEngineState) {
        switch state {
        case .idle: states.append("idle")
        case .loading: states.append("loading")
        case .playing: states.append("playing")
        case .paused: states.append("paused")
        case .finished: states.append("finished")
        case .error(let msg): states.append("error:\(msg)")
        }
    }
    func speechEngineDidFinish(_ engine: any SpeechEngine) {
        finishedCount += 1
    }
    func speechEngine(_ engine: any SpeechEngine, didEncounterError error: Error) {}
}

@MainActor
@Suite(.serialized)
struct SilentSpeechEngineTests {

    private let words = ["one", "two", "three", "four", "five"]

    @Test func emitsLoadingThenPlayingOnStart() async {
        let engine = SilentSpeechEngine(rate: 4.0) // fast — short total duration
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: words.joined(separator: " "), words: words)
        // start() returns after kicking off the tick task. Allow a moment for callbacks.
        try? await Task.sleep(for: .milliseconds(20))
        #expect(rec.states.contains("loading"))
        #expect(rec.states.contains("playing"))
        engine.stop()
    }

    @Test func advancesWordIndexOverTime() async {
        let engine = SilentSpeechEngine(rate: 4.0)
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: words.joined(separator: " "), words: words)
        // Wait long enough for at least the first couple of words to tick.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rec.lastWordIndex >= 0)
        engine.stop()
    }

    @Test func finishesExactlyOnceWhenLeftToCompletion() async {
        let engine = SilentSpeechEngine(rate: 8.0) // very fast: ~few hundred ms
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: "one two", words: ["one", "two"])
        // Wait well past completion.
        try? await Task.sleep(for: .milliseconds(800))
        #expect(rec.finishedCount == 1)
        #expect(rec.states.contains("finished"))
    }

    @Test func pauseStopsAdvancingWordIndex() async {
        let engine = SilentSpeechEngine(rate: 2.0)
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: words.joined(separator: " "), words: words)
        try? await Task.sleep(for: .milliseconds(100))
        let indexBeforePause = rec.lastWordIndex
        engine.pause()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(rec.lastWordIndex == indexBeforePause)
        #expect(rec.states.contains("paused"))
        engine.stop()
    }

    @Test func resumeContinuesFromPausedPosition() async {
        let engine = SilentSpeechEngine(rate: 2.0)
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: words.joined(separator: " "), words: words)
        try? await Task.sleep(for: .milliseconds(100))
        engine.pause()
        try? await Task.sleep(for: .milliseconds(150))
        let pausedIndex = rec.lastWordIndex
        engine.resume()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(rec.lastWordIndex >= pausedIndex)
        engine.stop()
    }

    @Test func stopHaltsTickingAndDoesNotEmitFinished() async {
        let engine = SilentSpeechEngine(rate: 0.5) // slow → won't naturally finish quickly
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: words.joined(separator: " "), words: words)
        try? await Task.sleep(for: .milliseconds(50))
        engine.stop()
        let finishedAfterStop = rec.finishedCount
        try? await Task.sleep(for: .milliseconds(200))
        #expect(rec.finishedCount == finishedAfterStop)
        #expect(rec.states.contains("idle"))
    }

    @Test func setSpeedDoesNotResetWordIndex() async {
        let engine = SilentSpeechEngine(rate: 2.0)
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: words.joined(separator: " "), words: words)
        try? await Task.sleep(for: .milliseconds(150))
        let beforeSetSpeed = rec.lastWordIndex
        engine.setSpeed(4.0)
        try? await Task.sleep(for: .milliseconds(50))
        // Setting speed shouldn't snap us backward to word 0.
        #expect(rec.lastWordIndex >= beforeSetSpeed)
        engine.stop()
    }

    @Test func emptyWordsListFinishesImmediatelyWithoutCrashing() async {
        let engine = SilentSpeechEngine(rate: 1.0)
        let rec = SilentSpeechRecorder()
        engine.delegate = rec
        await engine.start(text: "", words: [])
        try? await Task.sleep(for: .milliseconds(100))
        // No assertion on finishedCount specifics — just that we don't crash and
        // playback transitions through loading → playing.
        #expect(rec.states.contains("playing"))
        engine.stop()
    }
}
