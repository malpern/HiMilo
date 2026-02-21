@testable import VoxClawCore
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct NetworkListenerIntegrationTests {
    /// Use a high port unlikely to conflict; all tests share this port since the suite is serialized
    private static let testPort: UInt16 = 58_273

    @Test func statusEndpointReturnsOK() async throws {
        let appState = AppState()
        let listener = NetworkListener(port: Self.testPort, serviceName: nil, appState: appState)

        try listener.start { _ in }
        defer { listener.stop() }

        try await waitForListener(port: Self.testPort)

        // GET /status
        let url = URL(string: "http://localhost:\(Self.testPort)/status")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("ok"))
        #expect(body.contains("VoxClaw"))
        // Should include reading state
        #expect(body.contains("\"reading\":false"))
        #expect(body.contains("\"state\":\"idle\""))
        // Canonical endpoint fields should always be present for agents
        #expect(body.contains("\"speak_url\""))
        #expect(body.contains("\"health_url\""))
        // Agent guidance should not auto-route to .local hostnames
        #expect(!body.contains(".local"))
    }

    @Test func readEndpointAcceptsJSON() async throws {
        let appState = AppState()
        let listener = NetworkListener(port: Self.testPort, serviceName: nil, appState: appState)
        var receivedRequests: [ReadRequest] = []

        try listener.start { request in
            await MainActor.run { receivedRequests.append(request) }
        }
        defer { listener.stop() }

        try await waitForListener(port: Self.testPort)

        // POST /read with JSON body
        let url = URL(string: "http://localhost:\(Self.testPort)/read")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"text\":\"integration test\"}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("reading"))

        try await Task.sleep(for: .milliseconds(100))
        #expect(receivedRequests.contains { $0.text == "integration test" })
    }

    @Test func readEndpointAcceptsVoiceAndRate() async throws {
        let appState = AppState()
        let listener = NetworkListener(port: Self.testPort, serviceName: nil, appState: appState)
        var receivedRequests: [ReadRequest] = []

        try listener.start { request in
            await MainActor.run { receivedRequests.append(request) }
        }
        defer { listener.stop() }

        try await waitForListener(port: Self.testPort)

        // POST /read with voice and rate
        let url = URL(string: "http://localhost:\(Self.testPort)/read")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"text\":\"hello\",\"voice\":\"nova\",\"rate\":1.5}".data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)

        try await Task.sleep(for: .milliseconds(100))
        let received = try #require(receivedRequests.first { $0.text == "hello" })
        #expect(received.voice == "nova")
        #expect(received.rate == 1.5)
    }

    @Test func readEndpointAcceptsPlainText() async throws {
        let appState = AppState()
        let listener = NetworkListener(port: Self.testPort, serviceName: nil, appState: appState)
        var receivedRequests: [ReadRequest] = []

        try listener.start { request in
            await MainActor.run { receivedRequests.append(request) }
        }
        defer { listener.stop() }

        try await waitForListener(port: Self.testPort)

        // POST /read with plain text body
        let url = URL(string: "http://localhost:\(Self.testPort)/read")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "plain text body".data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)

        try await Task.sleep(for: .milliseconds(100))
        #expect(receivedRequests.contains { $0.text == "plain text body" })
    }

    @Test func notFoundForUnknownRoute() async throws {
        let appState = AppState()
        let listener = NetworkListener(port: Self.testPort, serviceName: nil, appState: appState)

        try listener.start { _ in }
        defer { listener.stop() }

        try await waitForListener(port: Self.testPort)

        // GET /unknown
        let url = URL(string: "http://localhost:\(Self.testPort)/unknown")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 404)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("error"))
    }

    // MARK: - Helpers

    /// Poll until the listener accepts connections (max 2 seconds)
    private func waitForListener(port: UInt16) async throws {
        let url = URL(string: "http://localhost:\(port)/status")!
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return }
            } catch {
                continue
            }
        }
        Issue.record("Listener did not become ready on port \(port)")
    }
}
