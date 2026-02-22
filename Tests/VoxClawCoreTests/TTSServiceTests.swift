@testable import VoxClawCore
import Foundation
import Testing

struct TTSServiceTests {
    // MARK: - httpError

    @Test func httpErrorPreservesStatusCodeForAuthFailures() {
        let error = TTSService.httpError(status: 401, body: #"{"error":"invalid key"}"#)
        #expect(error.statusCode == 401)
        #expect(error.message.contains("Invalid OpenAI API key"))
    }

    @Test func httpErrorUsesBodyForUnknownStatuses() {
        let error = TTSService.httpError(status: 418, body: "teapot body")
        #expect(error.statusCode == 418)
        #expect(error.message.contains("HTTP 418"))
        #expect(error.message.contains("teapot body"))
    }

    @Test func httpErrorHandlesRateLimit() {
        let error = TTSService.httpError(status: 429, body: "")
        #expect(error.statusCode == 429)
        #expect(error.message.contains("rate limit"))
    }

    @Test func httpErrorHandlesBadRequest() {
        let error = TTSService.httpError(status: 400, body: "")
        #expect(error.statusCode == 400)
        #expect(error.message.contains("rejected"))
    }

    @Test func httpErrorHandlesServerError() {
        let error = TTSService.httpError(status: 503, body: "")
        #expect(error.statusCode == 503)
        #expect(error.message.contains("unavailable"))
    }

    // MARK: - buildRequest

    @Test func buildRequestSetsCorrectURL() throws {
        let request = try TTSService.buildRequest(
            text: "Hello", apiKey: "sk-test", voice: "onyx"
        )
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
    }

    @Test func buildRequestSetsAuthorizationHeader() throws {
        let request = try TTSService.buildRequest(
            text: "Hello", apiKey: "sk-test-key-123", voice: "onyx"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key-123")
    }

    @Test func buildRequestSetsContentTypeJSON() throws {
        let request = try TTSService.buildRequest(
            text: "Hello", apiKey: "sk-test", voice: "onyx"
        )
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func buildRequestUsesPOSTMethod() throws {
        let request = try TTSService.buildRequest(
            text: "Hello", apiKey: "sk-test", voice: "onyx"
        )
        #expect(request.httpMethod == "POST")
    }

    @Test func buildRequestBodyContainsExpectedFields() throws {
        let request = try TTSService.buildRequest(
            text: "Test text", apiKey: "sk-test", voice: "nova",
            speed: 1.5, responseFormat: "mp3"
        )
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["input"] as? String == "Test text")
        #expect(json["voice"] as? String == "nova")
        #expect(json["response_format"] as? String == "mp3")
        #expect(json["speed"] as? Double == 1.5)
        #expect(json["model"] as? String == "gpt-4o-mini-tts")
    }

    @Test func buildRequestIncludesInstructionsWhenProvided() throws {
        let request = try TTSService.buildRequest(
            text: "Hello", apiKey: "sk-test", voice: "onyx",
            instructions: "Speak warmly"
        )
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["instructions"] as? String == "Speak warmly")
    }

    @Test func buildRequestOmitsInstructionsWhenNil() throws {
        let request = try TTSService.buildRequest(
            text: "Hello", apiKey: "sk-test", voice: "onyx",
            instructions: nil
        )
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["instructions"] == nil)
    }

    @Test func buildRequestOmitsEmptyInstructions() throws {
        let request = try TTSService.buildRequest(
            text: "Hello", apiKey: "sk-test", voice: "onyx",
            instructions: ""
        )
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["instructions"] == nil)
    }
}
