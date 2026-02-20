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

    // MARK: - parseReadRequest

    @Test func parseReadRequestJSON() {
        let req = NetworkSession.parseReadRequest(from: "{\"text\":\"hello world\"}")
        #expect(req?.text == "hello world")
        #expect(req?.voice == nil)
        #expect(req?.rate == nil)
    }

    @Test func parseReadRequestWithVoiceAndRate() {
        let req = NetworkSession.parseReadRequest(from: "{\"text\":\"hello\",\"voice\":\"nova\",\"rate\":1.5}")
        #expect(req?.text == "hello")
        #expect(req?.voice == "nova")
        #expect(req?.rate == 1.5)
    }

    @Test func parseReadRequestPlainText() {
        let req = NetworkSession.parseReadRequest(from: "hello world")
        #expect(req?.text == "hello world")
        #expect(req?.voice == nil)
    }

    @Test func parseReadRequestEmpty() {
        #expect(NetworkSession.parseReadRequest(from: "") == nil)
    }

    @Test func parseReadRequestWhitespaceOnly() {
        #expect(NetworkSession.parseReadRequest(from: "   \n  ") == nil)
    }

    @Test func parseReadRequestInvalidJSON() {
        // Invalid JSON falls back to plain text
        let req = NetworkSession.parseReadRequest(from: "{not json}")
        #expect(req?.text == "{not json}")
    }

    @Test func parseReadRequestJSONWithExtraFields() {
        let req = NetworkSession.parseReadRequest(from: "{\"text\":\"hello\",\"extra\":true}")
        #expect(req?.text == "hello")
    }

    @Test func parseReadRequestVoiceOnly() {
        let req = NetworkSession.parseReadRequest(from: "{\"text\":\"hi\",\"voice\":\"alloy\"}")
        #expect(req?.text == "hi")
        #expect(req?.voice == "alloy")
        #expect(req?.rate == nil)
    }

    @Test func parseReadRequestRateOnly() {
        let req = NetworkSession.parseReadRequest(from: "{\"text\":\"hi\",\"rate\":2.0}")
        #expect(req?.text == "hi")
        #expect(req?.voice == nil)
        #expect(req?.rate == 2.0)
    }
}
