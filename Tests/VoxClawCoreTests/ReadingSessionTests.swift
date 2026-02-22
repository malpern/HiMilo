@testable import VoxClawCore
import Foundation
import Testing

/// A mock speech engine for testing ReadingSession's delegate behavior.
@MainActor
final class MockSpeechEngine: SpeechEngine {
    weak var delegate: SpeechEngineDelegate?
    private(set) var state: SpeechEngineState = .idle

    var startCalled = false
    var pauseCalled = false
    var resumeCalled = false
    var stopCalled = false

    func start(text: String, words: [String]) async {
        startCalled = true
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    func pause() {
        pauseCalled = true
        state = .paused
        delegate?.speechEngine(self, didChangeState: .paused)
    }

    func resume() {
        resumeCalled = true
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
    }

    func stop() {
        stopCalled = true
        state = .idle
        delegate?.speechEngine(self, didChangeState: .idle)
    }

    func setSpeed(_ speed: Float) {}

    /// Simulate a word index update from the engine.
    func simulateWordIndex(_ index: Int) {
        delegate?.speechEngine(self, didUpdateWordIndex: index)
    }

    /// Simulate the engine finishing playback.
    func simulateFinish() {
        state = .finished
        delegate?.speechEngineDidFinish(self)
    }
}

@MainActor
struct ReadingSessionTests {
    @Test func sessionUpdatesWordIndexOnCallback() async {
        let appState = AppState()
        appState.audioOnly = true // skip panel
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)

        await session.start(text: "hello world test")
        #expect(engine.startCalled)
        #expect(appState.currentWordIndex == 0)

        engine.simulateWordIndex(1)
        #expect(appState.currentWordIndex == 1)

        engine.simulateWordIndex(2)
        #expect(appState.currentWordIndex == 2)
    }

    @Test func sessionPauseAndResume() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)

        await session.start(text: "hello world")

        session.togglePause()
        #expect(engine.pauseCalled)
        #expect(appState.isPaused)

        session.togglePause()
        #expect(engine.resumeCalled)
        #expect(!appState.isPaused)
    }

    @Test func sessionStopCallsEngine() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)

        await session.start(text: "hello world")
        session.stop()

        #expect(engine.stopCalled)
    }

    @Test func sessionFinishesOnEngineFinish() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)

        await session.start(text: "hello world")
        #expect(appState.sessionState == .playing)

        engine.simulateFinish()
        #expect(appState.sessionState == .finished)
    }

    @Test func stopForReplacementDoesNotResetSharedState() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)

        await session.start(text: "hello world")
        #expect(!appState.words.isEmpty)

        session.stopForReplacement()
        #expect(engine.stopCalled)
        #expect(!appState.words.isEmpty) // replacement path must not wipe current UI state
    }

    @Test func stopForReplacementCancelsPendingDelayedReset() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)

        await session.start(text: "hello world")
        #expect(!appState.words.isEmpty)

        // Simulate natural finish, which schedules delayed reset.
        engine.simulateFinish()
        #expect(appState.sessionState == .finished)

        // Replacement should cancel any pending delayed reset task.
        session.stopForReplacement()
        try? await Task.sleep(for: .milliseconds(700))

        #expect(!appState.words.isEmpty)
    }
}
