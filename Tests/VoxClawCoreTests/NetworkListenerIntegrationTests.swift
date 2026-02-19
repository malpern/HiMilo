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
        var receivedTexts: [String] = []

        try listener.start { text in
            await MainActor.run { receivedTexts.append(text) }
        }
        defer { listener.stop() }

        // Wait for listener to be ready
        try await waitForListener(port: Self.testPort)

        // GET /status
        let url = URL(string: "http://localhost:\(Self.testPort)/status")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("ok"))
        #expect(body.contains("VoxClaw"))
    }

    @Test func readEndpointAcceptsJSON() async throws {
        let appState = AppState()
        let listener = NetworkListener(port: Self.testPort, serviceName: nil, appState: appState)
        var receivedTexts: [String] = []

        try listener.start { text in
            await MainActor.run { receivedTexts.append(text) }
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

        // Give the callback a moment to fire
        try await Task.sleep(for: .milliseconds(100))
        #expect(receivedTexts.contains("integration test"))
    }

    @Test func readEndpointAcceptsPlainText() async throws {
        let appState = AppState()
        let listener = NetworkListener(port: Self.testPort, serviceName: nil, appState: appState)
        var receivedTexts: [String] = []

        try listener.start { text in
            await MainActor.run { receivedTexts.append(text) }
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
        #expect(receivedTexts.contains("plain text body"))
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
