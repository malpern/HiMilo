@testable import VoxClawCore
import Testing

@MainActor
struct AppleSpeechEngineTests {
    @Test func buildCharMapSimple() {
        let text = "hello world"
        let words = ["hello", "world"]
        let map = AppleSpeechEngine.buildCharMap(text: text, words: words)

        #expect(map.count == 2)
        #expect(map[0].range == 0..<5)
        #expect(map[0].wordIndex == 0)
        #expect(map[1].range == 6..<11)
        #expect(map[1].wordIndex == 1)
    }

    @Test func buildCharMapWithPunctuation() {
        let text = "hello, world!"
        let words = ["hello,", "world!"]
        let map = AppleSpeechEngine.buildCharMap(text: text, words: words)

        #expect(map.count == 2)
        #expect(map[0].range == 0..<6)
        #expect(map[1].range == 7..<13)
    }

    @Test func buildCharMapEmpty() {
        let map = AppleSpeechEngine.buildCharMap(text: "", words: [])
        #expect(map.isEmpty)
    }

    @Test func buildCharMapSingleWord() {
        let text = "hello"
        let words = ["hello"]
        let map = AppleSpeechEngine.buildCharMap(text: text, words: words)

        #expect(map.count == 1)
        #expect(map[0].range == 0..<5)
        #expect(map[0].wordIndex == 0)
    }

    @Test func wordIndexForValidOffset() {
        let map = AppleSpeechEngine.buildCharMap(text: "hello world", words: ["hello", "world"])

        // offset 0 is in "hello" (range 0..<5)
        var found: Int?
        for entry in map where entry.range.contains(0) {
            found = entry.wordIndex
        }
        #expect(found == 0)

        // offset 6 is in "world" (range 6..<11)
        found = nil
        for entry in map where entry.range.contains(6) {
            found = entry.wordIndex
        }
        #expect(found == 1)
    }

    @Test func wordIndexForOutOfRangeOffset() {
        let map = AppleSpeechEngine.buildCharMap(text: "hello world", words: ["hello", "world"])
        // offset 5 is the space, not in any word
        var found: Int?
        for entry in map where entry.range.contains(5) {
            found = entry.wordIndex
        }
        #expect(found == nil)
    }

    @Test func initialStateIsIdle() {
        let engine = AppleSpeechEngine()
        guard case .idle = engine.state else {
            Issue.record("Expected .idle, got \(engine.state)")
            return
        }
    }
}
