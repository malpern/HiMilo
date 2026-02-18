import Foundation
import Network

final class NetworkSession: Sendable {
    private let connection: NWConnection
    private let onTextReceived: @Sendable (String) async -> Void

    init(connection: NWConnection, onTextReceived: @escaping @Sendable (String) async -> Void) {
        self.connection = connection
        self.onTextReceived = onTextReceived
    }

    func start() {
        connection.start(queue: .main)
        receiveData()
    }

    private func receiveData() {
        // Read up to 1MB of data
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self, let data, error == nil else {
                self?.connection.cancel()
                return
            }

            let text = self.parseText(from: data)

            if !text.isEmpty {
                Task { @MainActor in
                    await self.onTextReceived(text)
                    self.sendResponse()
                }
            } else if !isComplete {
                self.receiveData()
            } else {
                self.connection.cancel()
            }
        }
    }

    private func parseText(from data: Data) -> String {
        guard let raw = String(data: data, encoding: .utf8) else { return "" }

        // Check if this is an HTTP request
        if raw.hasPrefix("POST") || raw.hasPrefix("GET") || raw.hasPrefix("PUT") {
            return parseHTTPBody(raw)
        }

        // Raw TCP — treat entire payload as text
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseHTTPBody(_ request: String) -> String {
        // Split headers from body at double newline
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else { return "" }

        let body = parts.dropFirst().joined(separator: "\r\n\r\n")

        // Try JSON parse
        if let jsonData = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let text = json["text"] as? String {
            return text
        }

        // Fall back to plain text body
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendResponse() {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Connection: close\r
        \r
        {"status":"reading"}
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }
}
