import Foundation

/// The state a speech engine can be in.
enum SpeechEngineState: Sendable {
    case idle
    case loading
    case playing
    case paused
    case finished
    case error(String)
}

/// Callbacks from the engine to the session layer.
@MainActor
protocol SpeechEngineDelegate: AnyObject {
    func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int)
    func speechEngineDidFinish(_ engine: any SpeechEngine)
    func speechEngine(_ engine: any SpeechEngine, didChangeState state: SpeechEngineState)
    func speechEngine(_ engine: any SpeechEngine, didEncounterError error: Error)
}

/// Abstraction over any TTS backend (Apple Speech or OpenAI).
@MainActor
protocol SpeechEngine: AnyObject {
    var delegate: SpeechEngineDelegate? { get set }
    var state: SpeechEngineState { get }

    /// Begin speaking the given text. The words array is the pre-split word list
    /// so the engine can map callbacks to word indices.
    func start(text: String, words: [String]) async

    func pause()
    func resume()
    func stop()
}
