import Foundation
import os

/// Wraps a primary engine and retries once with a fallback engine if the primary errors.
@MainActor
final class FallbackSpeechEngine: SpeechEngine, SpeechEngineDelegate {
    weak var delegate: SpeechEngineDelegate?
    private(set) var state: SpeechEngineState = .idle

    private let primary: any SpeechEngine
    private let fallback: any SpeechEngine
    private var active: any SpeechEngine
    private var didFallback = false
    private var lastText = ""
    private var lastWords: [String] = []

    init(primary: any SpeechEngine, fallback: any SpeechEngine) {
        self.primary = primary
        self.fallback = fallback
        self.active = primary
        self.primary.delegate = self
        self.fallback.delegate = self
    }

    func start(text: String, words: [String]) async {
        lastText = text
        lastWords = words
        didFallback = false
        active = primary
        state = .loading
        delegate?.speechEngine(self, didChangeState: .loading)
        await primary.start(text: text, words: words)
    }

    func pause() {
        active.pause()
    }

    func resume() {
        active.resume()
    }

    func stop() {
        active.stop()
    }

    // MARK: - SpeechEngineDelegate passthrough

    func speechEngine(_ engine: any SpeechEngine, didUpdateWordIndex index: Int) {
        guard isActive(engine) else { return }
        delegate?.speechEngine(self, didUpdateWordIndex: index)
    }

    func speechEngineDidFinish(_ engine: any SpeechEngine) {
        guard isActive(engine) else { return }
        state = .finished
        delegate?.speechEngineDidFinish(self)
    }

    func speechEngine(_ engine: any SpeechEngine, didChangeState state: SpeechEngineState) {
        guard isActive(engine) else { return }
        self.state = state
        delegate?.speechEngine(self, didChangeState: state)
    }

    func speechEngine(_ engine: any SpeechEngine, didEncounterError error: Error) {
        guard isActive(engine) else { return }

        if !didFallback, isPrimary(engine) {
            didFallback = true
            active = fallback
            Log.tts.warning("Primary speech engine failed; falling back to Apple voice. Error: \(error)")
            delegate?.speechEngine(self, didChangeState: .loading)
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.fallback.start(text: self.lastText, words: self.lastWords)
            }
            return
        }

        state = .error(error.localizedDescription)
        delegate?.speechEngine(self, didEncounterError: error)
    }

    private func isActive(_ engine: any SpeechEngine) -> Bool {
        ObjectIdentifier(engine as AnyObject) == ObjectIdentifier(active as AnyObject)
    }

    private func isPrimary(_ engine: any SpeechEngine) -> Bool {
        ObjectIdentifier(engine as AnyObject) == ObjectIdentifier(primary as AnyObject)
    }
}
