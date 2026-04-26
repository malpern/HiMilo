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
    var onStart: (() -> Void)?
    func start(text: String, words: [String]) async {
        startCalled = true
        onStart?()
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
    func simulateError(_ message: String = "boom") {
        state = .error(message)
        delegate?.speechEngine(self, didEncounterError: NSError(domain: "ReadingSessionTests", code: 1))
    }
}
@MainActor
final class MockPlaybackController: ExternalPlaybackControlling {
    var pauseCallCount = 0
    var resumedSnapshots: [PlaybackSnapshot] = []
    var snapshotToReturn: PlaybackSnapshot?
    var onPause: (() -> Void)?
    func pauseIfPlaying() -> PlaybackSnapshot? {
        pauseCallCount += 1
        onPause?()
        return snapshotToReturn
    }
    func resume(_ snapshot: PlaybackSnapshot) {
        resumedSnapshots.append(snapshot)
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
    @Test func sessionPausesExternalPlaybackBeforeSpeechStarts() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let controller = MockPlaybackController()
        controller.snapshotToReturn = PlaybackSnapshot()
        engine.onStart = {
            #expect(controller.pauseCallCount == 1)
        }
        let session = ReadingSession(
            appState: appState,
            engine: engine,
            pauseExternalAudioDuringSpeech: true,
            playbackController: controller
        )
        await session.start(text: "hello world")
        #expect(engine.startCalled)
        #expect(controller.pauseCallCount == 1)
    }
    @Test func sessionResumesExternalPlaybackOnFinish() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let controller = MockPlaybackController()
        let snapshot = PlaybackSnapshot()
        controller.snapshotToReturn = snapshot
        let session = ReadingSession(
            appState: appState,
            engine: engine,
            pauseExternalAudioDuringSpeech: true,
            playbackController: controller
        )
        await session.start(text: "hello world")
        engine.simulateFinish()
        #expect(controller.resumedSnapshots == [snapshot])
    }
    @Test func sessionResumesExternalPlaybackOnStop() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let controller = MockPlaybackController()
        let snapshot = PlaybackSnapshot()
        controller.snapshotToReturn = snapshot
        let session = ReadingSession(
            appState: appState,
            engine: engine,
            pauseExternalAudioDuringSpeech: true,
            playbackController: controller
        )
        await session.start(text: "hello world")
        session.stop()
        #expect(controller.resumedSnapshots == [snapshot])
    }
    @Test func sessionResumesExternalPlaybackOnReplacement() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let controller = MockPlaybackController()
        let snapshot = PlaybackSnapshot()
        controller.snapshotToReturn = snapshot
        let session = ReadingSession(
            appState: appState,
            engine: engine,
            pauseExternalAudioDuringSpeech: true,
            playbackController: controller
        )
        await session.start(text: "hello world")
        session.stopForReplacement()
        #expect(controller.resumedSnapshots == [snapshot])
    }
    @Test func sessionResumesExternalPlaybackOnError() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let controller = MockPlaybackController()
        let snapshot = PlaybackSnapshot()
        controller.snapshotToReturn = snapshot
        let session = ReadingSession(
            appState: appState,
            engine: engine,
            pauseExternalAudioDuringSpeech: true,
            playbackController: controller
        )
        await session.start(text: "hello world")
        engine.simulateError()
        #expect(controller.resumedSnapshots == [snapshot])
    }
    @Test func sessionDoesNotResumeWhenNothingWasPaused() async {
        let appState = AppState()
        appState.audioOnly = true
        let engine = MockSpeechEngine()
        let controller = MockPlaybackController()
        let session = ReadingSession(
            appState: appState,
            engine: engine,
            pauseExternalAudioDuringSpeech: true,
            playbackController: controller
        )
        await session.start(text: "hello world")
        engine.simulateFinish()
        #expect(controller.resumedSnapshots.isEmpty)
    }
    @Test func pauseForBlockerSetsFlag() async {
        let appState = AppState()
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)
        await session.start(text: "hello world")
        session.pauseForBlocker()
        #expect(engine.pauseCalled)
        #expect(appState.isPaused)
    }
    @Test func resumeFromBlockerOnlyWhenBlockerPaused() async {
        let appState = AppState()
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)
        await session.start(text: "hello world")
        // Manual pause — not blocker-initiated
        session.togglePause()
        #expect(appState.isPaused)
        // resumeFromBlocker should NOT resume a manual pause
        session.resumeFromBlocker()
        #expect(appState.isPaused)
    }
    @Test func resumeFromBlockerWorksAfterBlockerPause() async {
        let appState = AppState()
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)
        await session.start(text: "hello world")
        session.pauseForBlocker()
        #expect(appState.isPaused)
        session.resumeFromBlocker()
        #expect(!appState.isPaused)
        #expect(engine.resumeCalled)
    }
    @Test func waitUntilFinishedReturnsOnEngineFinish() async {
        let appState = AppState()
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)
        await session.start(text: "hello")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            engine.simulateFinish()
        }
        await session.waitUntilFinished()
        #expect(session.hasFinished)
    }
    @Test func keepPanelOnFinishClearsWordsButStaysFinalized() async {
        let appState = AppState()
        let engine = MockSpeechEngine()
        let session = ReadingSession(appState: appState, engine: engine)
        session.keepPanelOnFinish = true
        await session.start(text: "hello world test")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            engine.simulateFinish()
        }
        await session.waitUntilFinished()
        // Words should be cleared but session is finalized
        try? await Task.sleep(for: .milliseconds(400))
        #expect(appState.words.isEmpty)
        #expect(session.hasFinished)
    }
}
