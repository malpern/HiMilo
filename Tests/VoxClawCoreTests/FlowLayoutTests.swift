@testable import VoxClawCore
import SwiftUI
import Testing

@MainActor
struct FlowLayoutTests {

    @Test func paragraphSentinelDoesNotInflateWidth() {
        let text = "Hello world.\n\nSecond paragraph here."
        let words = ReadingSession.splitPreservingParagraphs(text)
        #expect(words.contains(ReadingSession.paragraphSentinel))
        let sentinelCount = words.filter { $0 == ReadingSession.paragraphSentinel }.count
        #expect(sentinelCount == 1)
    }

    @Test func splitPreservingParagraphsHandlesNoParagraphs() {
        let words = ReadingSession.splitPreservingParagraphs("Hello world")
        #expect(words == ["Hello", "world"])
    }

    @Test func splitPreservingParagraphsHandlesMultipleParagraphs() {
        let words = ReadingSession.splitPreservingParagraphs("A B\n\nC D\n\nE")
        #expect(words == ["A", "B", "\u{2029}", "C", "D", "\u{2029}", "E"])
    }

    @Test func splitPreservingParagraphsSkipsLeadingTrailingSentinels() {
        let words = ReadingSession.splitPreservingParagraphs("\n\nHello\n\n")
        #expect(!words.isEmpty)
        #expect(words.first != ReadingSession.paragraphSentinel)
    }

    @Test func splitPreservingParagraphsHandlesEmptyText() {
        let words = ReadingSession.splitPreservingParagraphs("")
        #expect(words.isEmpty)
    }
}
