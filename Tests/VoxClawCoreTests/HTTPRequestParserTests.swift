@testable import VoxClawCore
import Testing

struct HTTPRequestParserTests {
    // MARK: - project_id / agent_id parsing

    @Test func parseReadRequestWithProjectAndAgentIds() {
        let body = #"{"text":"hi","project_id":"/tmp/proj","agent_id":"worker"}"#
        let req = HTTPRequestParser.parseReadRequest(from: body)
        #expect(req?.text == "hi")
        #expect(req?.projectId == "/tmp/proj")
        #expect(req?.agentId == "worker")
    }

    @Test func parseReadRequestEmptyProjectIdBecomesNil() {
        let body = #"{"text":"hi","project_id":"   ","agent_id":""}"#
        let req = HTTPRequestParser.parseReadRequest(from: body)
        #expect(req?.projectId == nil)
        #expect(req?.agentId == nil)
    }

    @Test func parseReadRequestWithoutIdentityFields() {
        let body = #"{"text":"hi"}"#
        let req = HTTPRequestParser.parseReadRequest(from: body)
        #expect(req?.projectId == nil)
        #expect(req?.agentId == nil)
    }

    // MARK: - parseContentLength

    @Test func parseContentLengthPresent() {
        let raw = "POST /read HTTP/1.1\r\nContent-Length: 42\r\nHost: localhost\r\n\r\n"
        #expect(HTTPRequestParser.parseContentLength(from: raw) == 42)
    }

    @Test func parseContentLengthMissing() {
        let raw = "POST /read HTTP/1.1\r\nHost: localhost\r\n\r\n"
        #expect(HTTPRequestParser.parseContentLength(from: raw) == nil)
    }

    @Test func parseContentLengthCaseInsensitive() {
        let raw = "POST /read HTTP/1.1\r\ncontent-length: 100\r\n\r\n"
        #expect(HTTPRequestParser.parseContentLength(from: raw) == 100)
    }

    @Test func parseContentLengthZero() {
        let raw = "POST /read HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        #expect(HTTPRequestParser.parseContentLength(from: raw) == 0)
    }

    // MARK: - extractBody

    @Test func extractBodyPresent() {
        let raw = "POST /read HTTP/1.1\r\nHost: localhost\r\n\r\n{\"text\":\"hello\"}"
        #expect(HTTPRequestParser.extractBody(from: raw) == "{\"text\":\"hello\"}")
    }

    @Test func extractBodyEmpty() {
        let raw = "POST /read HTTP/1.1\r\nHost: localhost\r\n\r\n"
        #expect(HTTPRequestParser.extractBody(from: raw) == "")
    }

    @Test func extractBodyNoSeparator() {
        let raw = "POST /read HTTP/1.1"
        #expect(HTTPRequestParser.extractBody(from: raw) == "")
    }

    // MARK: - parseReadRequest

    @Test func parseReadRequestJSON() {
        let req = HTTPRequestParser.parseReadRequest(from: "{\"text\":\"hello world\"}")
        #expect(req?.text == "hello world")
        #expect(req?.voice == nil)
        #expect(req?.rate == nil)
    }

    @Test func parseReadRequestWithVoiceAndRate() {
        let req = HTTPRequestParser.parseReadRequest(from: "{\"text\":\"hello\",\"voice\":\"nova\",\"rate\":1.5}")
        #expect(req?.text == "hello")
        #expect(req?.voice == "nova")
        #expect(req?.rate == 1.5)
    }

    @Test func parseReadRequestPlainText() {
        let req = HTTPRequestParser.parseReadRequest(from: "hello world")
        #expect(req?.text == "hello world")
        #expect(req?.voice == nil)
    }

    @Test func parseReadRequestEmpty() {
        #expect(HTTPRequestParser.parseReadRequest(from: "") == nil)
    }

    @Test func parseReadRequestWhitespaceOnly() {
        #expect(HTTPRequestParser.parseReadRequest(from: "   \n  ") == nil)
    }

    @Test func parseReadRequestInvalidJSON() {
        // Invalid JSON falls back to plain text
        let req = HTTPRequestParser.parseReadRequest(from: "{not json}")
        #expect(req?.text == "{not json}")
    }

    @Test func parseReadRequestJSONWithExtraFields() {
        let req = HTTPRequestParser.parseReadRequest(from: "{\"text\":\"hello\",\"extra\":true}")
        #expect(req?.text == "hello")
    }

    @Test func parseReadRequestVoiceOnly() {
        let req = HTTPRequestParser.parseReadRequest(from: "{\"text\":\"hi\",\"voice\":\"alloy\"}")
        #expect(req?.text == "hi")
        #expect(req?.voice == "alloy")
        #expect(req?.rate == nil)
    }

    @Test func parseReadRequestRateOnly() {
        let req = HTTPRequestParser.parseReadRequest(from: "{\"text\":\"hi\",\"rate\":2.0}")
        #expect(req?.text == "hi")
        #expect(req?.voice == nil)
        #expect(req?.rate == 2.0)
    }

    // MARK: - parseRequestLine

    @Test func parseRequestLineValidGET() {
        let raw = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = HTTPRequestParser.parseRequestLine(from: raw)
        #expect(result?.method == "GET")
        #expect(result?.path == "/status")
    }

    @Test func parseRequestLineValidPOST() {
        let raw = "POST /read HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"text\":\"hi\"}"
        let result = HTTPRequestParser.parseRequestLine(from: raw)
        #expect(result?.method == "POST")
        #expect(result?.path == "/read")
    }

    @Test func parseRequestLineMissingPath() {
        let raw = "GET\r\n\r\n"
        #expect(HTTPRequestParser.parseRequestLine(from: raw) == nil)
    }

    @Test func parseRequestLineEmptyString() {
        #expect(HTTPRequestParser.parseRequestLine(from: "") == nil)
    }

    @Test func parseRequestLineMalformed() {
        let raw = "INVALID\r\nHost: localhost\r\n\r\n"
        #expect(HTTPRequestParser.parseRequestLine(from: raw) == nil)
    }

    // MARK: - route

    @Test func routeGetStatus() {
        #expect(HTTPRequestParser.route(method: "GET", path: "/status") == .status)
    }

    @Test func routePostRead() {
        #expect(HTTPRequestParser.route(method: "POST", path: "/read") == .read)
    }

    @Test func routeGetClaw() {
        #expect(HTTPRequestParser.route(method: "GET", path: "/claw") == .claw)
    }

    @Test func routeOptionsPreflight() {
        #expect(HTTPRequestParser.route(method: "OPTIONS", path: "/read") == .corsPreflight)
        #expect(HTTPRequestParser.route(method: "OPTIONS", path: "/anything") == .corsPreflight)
    }

    @Test func routeNotFound() {
        #expect(HTTPRequestParser.route(method: "GET", path: "/unknown") == .notFound(method: "GET", path: "/unknown"))
        #expect(HTTPRequestParser.route(method: "DELETE", path: "/read") == .notFound(method: "DELETE", path: "/read"))
    }
}
