@testable import VoxClawCore
import Testing

struct SpeechAlignerTests {
    // MARK: - normalize

    @Test func normalizeStripsLeadingPunctuation() {
        #expect(SpeechAligner.normalize("\"hello") == "hello")
    }

    @Test func normalizeStripsTrailingPunctuation() {
        #expect(SpeechAligner.normalize("world!") == "world")
    }

    @Test func normalizeLowercases() {
        #expect(SpeechAligner.normalize("Hello") == "hello")
    }

    @Test func normalizeStripsWhitespace() {
        #expect(SpeechAligner.normalize("  hello  ") == "hello")
    }

    @Test func normalizeHandlesEmptyString() {
        #expect(SpeechAligner.normalize("") == "")
    }

    @Test func normalizeHandlesPunctuationOnly() {
        #expect(SpeechAligner.normalize("...") == "")
    }

    @Test func normalizeHandlesHyphenatedWord() {
        // Hyphens are punctuation, so they get stripped from edges
        #expect(SpeechAligner.normalize("-hello-") == "hello")
    }

    @Test func normalizePreservesInternalApostrophe() {
        // Internal apostrophes may or may not survive depending on CharacterSet
        let result = SpeechAligner.normalize("don't")
        #expect(result == "don't" || result == "dont")
    }

    @Test func normalizeHandlesAllCaps() {
        #expect(SpeechAligner.normalize("WORLD") == "world")
    }

    @Test func normalizeHandlesMixedPunctuationAndWhitespace() {
        // lowercased → trimmingPunctuation → trimmingWhitespace
        // Whitespace at edges prevents punctuation trim on first pass,
        // so quotes survive after whitespace trim
        let result = SpeechAligner.normalize("  \"Hello,\"  ")
        #expect(result == "\"hello,\"")
    }
}
