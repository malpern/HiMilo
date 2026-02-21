@testable import VoxClawCore
import Foundation
import Testing

@MainActor
private final class TestSpeechEngine: SpeechEngine {
    weak var delegate: SpeechEngineDelegate?
    private(set) var state: SpeechEngineState = .idle

    var startCount = 0
    var shouldFailOnStart = false
    var finishOnStart = false

    func start(text: String, words: [String]) async {
        startCount += 1
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)
        if shouldFailOnStart {
            state = .error("failed")
            delegate?.speechEngine(self, didEncounterError: NSError(domain: "test", code: 1))
            return
        }
        state = .playing
        delegate?.speechEngine(self, didChangeState: .playing)
        if finishOnStart {
            state = .finished
            delegate?.speechEngineDidFinish(self)
        }
    }

    func pause() {}
    func resume() {}
    func stop() {}
}

@MainActor
private final class TestSessionDelegate: SpeechEngineDelegate {
    var didFinish = false
    var didError = false

    func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int) {}
    func speechEngineDidFinish(_ engine: any SpeechEngine) { didFinish = true }
    func speechEngine(_ engine: any SpeechEngine, didChangeState state: SpeechEngineState) {}
    func speechEngine(_ engine: any SpeechEngine, didEncounterError error: Error) { didError = true }
}

@MainActor
struct FallbackSpeechEngineTests {
    @Test func fallsBackWhenPrimaryFails() async throws {
        let primary = TestSpeechEngine()
        primary.shouldFailOnStart = true

        let fallback = TestSpeechEngine()
        fallback.finishOnStart = true

        let engine = FallbackSpeechEngine(primary: primary, fallback: fallback)
        let delegate = TestSessionDelegate()
        engine.delegate = delegate

        await engine.start(text: "hello world", words: ["hello", "world"])
        try await Task.sleep(for: .milliseconds(50))

        #expect(primary.startCount == 1)
        #expect(fallback.startCount == 1)
        #expect(delegate.didFinish)
        #expect(!delegate.didError)
    }
}
