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
        receiveHTTPRequest()
    }

    private func receiveHTTPRequest() {
        // Accumulate data until we have a complete HTTP request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            guard let data, error == nil else {
                connection.cancel()
                return
            }

            guard let raw = String(data: data, encoding: .utf8) else {
                sendErrorResponse(status: 400, message: "Invalid encoding")
                return
            }

            // Parse the HTTP request line
            let lines = raw.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else {
                sendErrorResponse(status: 400, message: "Empty request")
                return
            }

            let parts = requestLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else {
                sendErrorResponse(status: 400, message: "Malformed request line")
                return
            }

            let method = String(parts[0])
            let path = String(parts[1])

            // Route the request
            switch (method, path) {
            case ("GET", "/status"):
                handleStatus()
            case ("POST", "/read"):
                handleRead(raw: raw, initialData: data)
            case ("OPTIONS", _):
                // CORS preflight
                sendResponse(status: 204, body: nil)
            default:
                sendErrorResponse(status: 404, message: "Not found. Use POST /read or GET /status")
            }
        }
    }

    // MARK: - Route Handlers

    private func handleStatus() {
        let json = """
        {"status":"ok","service":"HiMilo"}
        """
        sendResponse(status: 200, body: json, contentType: "application/json")
    }

    private func handleRead(raw: String, initialData: Data) {
        // Find Content-Length header
        let contentLength = parseContentLength(from: raw)

        // Split headers from body
        guard let headerEndRange = raw.range(of: "\r\n\r\n") else {
            // Haven't received full headers yet, keep reading
            receiveMoreData(accumulated: initialData)
            return
        }

        let headerPortion = raw[raw.startIndex..<headerEndRange.lowerBound]
        let headerByteCount = headerPortion.utf8.count + 4 // +4 for \r\n\r\n
        let bodyBytes = initialData.count - headerByteCount

        if let contentLength, bodyBytes < contentLength {
            // Need to read more body data
            let remaining = contentLength - bodyBytes
            receiveBody(accumulated: initialData, remaining: remaining)
        } else {
            // We have the full request
            processFullRequest(data: initialData)
        }
    }

    private func receiveMoreData(accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            guard let data, error == nil else {
                processFullRequest(data: accumulated)
                return
            }
            var combined = accumulated
            combined.append(data)

            if isComplete {
                processFullRequest(data: combined)
            } else {
                // Check if we now have the full body
                if let raw = String(data: combined, encoding: .utf8),
                   let headerEndRange = raw.range(of: "\r\n\r\n") {
                    let headerByteCount = raw[raw.startIndex..<headerEndRange.lowerBound].utf8.count + 4
                    let bodyBytes = combined.count - headerByteCount
                    let contentLength = parseContentLength(from: raw)

                    if contentLength == nil || bodyBytes >= (contentLength ?? 0) {
                        processFullRequest(data: combined)
                        return
                    }
                }
                receiveMoreData(accumulated: combined)
            }
        }
    }

    private func receiveBody(accumulated: Data, remaining: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [self] data, _, _, error in
            guard let data, error == nil else {
                processFullRequest(data: accumulated)
                return
            }
            var combined = accumulated
            combined.append(data)

            let newRemaining = remaining - data.count
            if newRemaining <= 0 {
                processFullRequest(data: combined)
            } else {
                receiveBody(accumulated: combined, remaining: newRemaining)
            }
        }
    }

    // MARK: - Request Processing

    private func processFullRequest(data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else {
            sendErrorResponse(status: 400, message: "Invalid encoding")
            return
        }

        let body = extractBody(from: raw)
        let text = parseTextFromBody(body)

        guard !text.isEmpty else {
            sendErrorResponse(status: 400, message: "No text provided. Send JSON {\"text\":\"...\"} or plain text body.")
            return
        }

        Task {
            await onTextReceived(text)
            sendResponse(status: 200, body: "{\"status\":\"reading\"}", contentType: "application/json")
        }
    }

    private func extractBody(from raw: String) -> String {
        guard let range = raw.range(of: "\r\n\r\n") else { return "" }
        return String(raw[range.upperBound...])
    }

    private func parseTextFromBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Try JSON: {"text": "..."}
        if let jsonData = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let text = json["text"] as? String {
            return text
        }

        // Fall back to plain text body
        return trimmed
    }

    // MARK: - HTTP Helpers

    private func parseContentLength(from raw: String) -> Int? {
        for line in raw.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    private func sendResponse(status: Int, body: String?, contentType: String = "application/json") {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }

        var headers = "HTTP/1.1 \(status) \(statusText)\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        headers += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
        headers += "Access-Control-Allow-Headers: Content-Type\r\n"
        headers += "Connection: close\r\n"

        if let body {
            let bodyData = body.data(using: .utf8) ?? Data()
            headers += "Content-Type: \(contentType)\r\n"
            headers += "Content-Length: \(bodyData.count)\r\n"
            headers += "\r\n"
            var responseData = headers.data(using: .utf8) ?? Data()
            responseData.append(bodyData)
            connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        } else {
            headers += "\r\n"
            connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        }
    }

    private func sendErrorResponse(status: Int, message: String) {
        let body = "{\"error\":\"\(message)\"}"
        sendResponse(status: status, body: body, contentType: "application/json")
    }
}
