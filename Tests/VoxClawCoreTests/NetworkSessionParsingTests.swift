@testable import VoxClawCore
import Testing

struct NetworkSessionParsingTests {
    // MARK: - parseContentLength

    @Test func parseContentLengthPresent() {
        let raw = "POST /read HTTP/1.1\r\nContent-Length: 42\r\nHost: localhost\r\n\r\n"
        #expect(NetworkSession.parseContentLength(from: raw) == 42)
    }

    @Test func parseContentLengthMissing() {
        let raw = "POST /read HTTP/1.1\r\nHost: localhost\r\n\r\n"
        #expect(NetworkSession.parseContentLength(from: raw) == nil)
    }

    @Test func parseContentLengthCaseInsensitive() {
        let raw = "POST /read HTTP/1.1\r\ncontent-length: 100\r\n\r\n"
        #expect(NetworkSession.parseContentLength(from: raw) == 100)
    }

    @Test func parseContentLengthZero() {
        let raw = "POST /read HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        #expect(NetworkSession.parseContentLength(from: raw) == 0)
    }

    // MARK: - extractBody

    @Test func extractBodyPresent() {
        let raw = "POST /read HTTP/1.1\r\nHost: localhost\r\n\r\n{\"text\":\"hello\"}"
        #expect(NetworkSession.extractBody(from: raw) == "{\"text\":\"hello\"}")
    }

    @Test func extractBodyEmpty() {
        let raw = "POST /read HTTP/1.1\r\nHost: localhost\r\n\r\n"
        #expect(NetworkSession.extractBody(from: raw) == "")
    }

    @Test func extractBodyNoSeparator() {
        let raw = "POST /read HTTP/1.1"
        #expect(NetworkSession.extractBody(from: raw) == "")
    }

    // MARK: - parseTextFromBody

    @Test func parseTextFromBodyJSON() {
        #expect(NetworkSession.parseTextFromBody("{\"text\":\"hello world\"}") == "hello world")
    }

    @Test func parseTextFromBodyPlainText() {
        #expect(NetworkSession.parseTextFromBody("hello world") == "hello world")
    }

    @Test func parseTextFromBodyEmpty() {
        #expect(NetworkSession.parseTextFromBody("") == "")
    }

    @Test func parseTextFromBodyWhitespaceOnly() {
        #expect(NetworkSession.parseTextFromBody("   \n  ") == "")
    }

    @Test func parseTextFromBodyInvalidJSON() {
        // Invalid JSON falls back to plain text
        #expect(NetworkSession.parseTextFromBody("{not json}") == "{not json}")
    }

    @Test func parseTextFromBodyJSONWithExtraFields() {
        let json = "{\"text\":\"hello\",\"voice\":\"nova\"}"
        #expect(NetworkSession.parseTextFromBody(json) == "hello")
    }
}
