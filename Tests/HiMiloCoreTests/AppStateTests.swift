@testable import HiMiloCore
import Testing

@MainActor
struct AppStateTests {
    @Test func isActiveWhenPlaying() {
        let state = AppState()
        state.sessionState = .playing
        #expect(state.isActive)
    }

    @Test func isActiveWhenPaused() {
        let state = AppState()
        state.sessionState = .paused
        #expect(state.isActive)
    }

    @Test func isActiveWhenLoading() {
        let state = AppState()
        state.sessionState = .loading
        #expect(state.isActive)
    }

    @Test func isNotActiveWhenIdle() {
        let state = AppState()
        state.sessionState = .idle
        #expect(!state.isActive)
    }

    @Test func isNotActiveWhenFinished() {
        let state = AppState()
        state.sessionState = .finished
        #expect(!state.isActive)
    }

    @Test func resetClearsSessionState() {
        let state = AppState()
        state.sessionState = .playing
        state.words = ["hello", "world"]
        state.currentWordIndex = 5
        state.isPaused = true
        state.feedbackText = "test"
        state.inputText = "some input"

        state.reset()

        #expect(state.sessionState == .idle)
        #expect(state.words.isEmpty)
        #expect(state.currentWordIndex == 0)
        #expect(!state.isPaused)
        #expect(state.feedbackText == nil)
        #expect(state.inputText == "")
    }

    @Test func resetPreservesAudioOnlyAndListening() {
        let state = AppState()
        state.audioOnly = true
        state.isListening = true
        state.sessionState = .playing

        state.reset()

        #expect(state.audioOnly)
        #expect(state.isListening)
    }

    @Test func defaultState() {
        let state = AppState()
        #expect(state.sessionState == .idle)
        #expect(state.words.isEmpty)
        #expect(state.currentWordIndex == 0)
        #expect(!state.isPaused)
        #expect(!state.audioOnly)
        #expect(!state.isListening)
        #expect(state.feedbackText == nil)
        #expect(state.inputText == "")
    }
}
