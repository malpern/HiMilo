import Foundation
import Network
import os

final class NetworkSession: Sendable {
    private let connection: NWConnection
    private let onReadRequest: @Sendable (ReadRequest) async -> Void
    private let onAgentNotificationRequest: @Sendable (AgentNotificationRequest) async -> AgentNotificationOutcome
    private let statusProvider: @Sendable () async -> (
        reading: Bool,
        state: String,
        wordCount: Int,
        port: UInt16,
        lanIP: String?,
        autoClosedInstancesOnLaunch: Int,
        agentSpeechMode: AgentSpeechMode,
        agentSpeechVerbosity: AgentSpeechVerbosity,
        voiceBindingCount: Int
    )

    init(
        connection: NWConnection,
        statusProvider: @escaping @Sendable () async -> (
            reading: Bool,
            state: String,
            wordCount: Int,
            port: UInt16,
            lanIP: String?,
            autoClosedInstancesOnLaunch: Int,
            agentSpeechMode: AgentSpeechMode,
            agentSpeechVerbosity: AgentSpeechVerbosity,
            voiceBindingCount: Int
        ),
        onReadRequest: @escaping @Sendable (ReadRequest) async -> Void,
        onAgentNotificationRequest: @escaping @Sendable (AgentNotificationRequest) async -> AgentNotificationOutcome
    ) {
        self.connection = connection
        self.statusProvider = statusProvider
        self.onReadRequest = onReadRequest
        self.onAgentNotificationRequest = onAgentNotificationRequest
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

            guard let (method, path) = HTTPRequestParser.parseRequestLine(from: raw) else {
                sendErrorResponse(status: 400, message: "Malformed request line")
                return
            }

            Log.network.debug("Request: \(method, privacy: .public) \(path, privacy: .public)")

            switch HTTPRequestParser.route(method: method, path: path) {
            case .status:
                Task { await self.handleStatus() }
            case .read:
                handleRead(raw: raw, initialData: data)
            case .agentNotify:
                handleAgentNotify(raw: raw, initialData: data)
            case .claw:
                handleClaw()
            case .corsPreflight:
                sendResponse(status: 204, body: nil)
            case .notFound:
                Log.network.info("404: \(method, privacy: .public) \(path, privacy: .public)")
                sendErrorResponse(status: 404, message: "Not found. Use POST /read or GET /status")
            }
        }
    }

    // MARK: - Route Handlers

    private func handleStatus() async {
        let info = await statusProvider()
        let ip = info.lanIP ?? "<lan-ip>"
        let baseURL = "http://\(ip):\(info.port)"
        let payload: [String: Any] = [
            "status": "ok",
            "service": "VoxClaw",
            "reading": info.reading,
            "state": info.state,
            "word_count": info.wordCount,
            "website": "https://voxclaw.com/",
            "skill_doc": "https://github.com/malpern/VoxClaw/blob/main/SKILL.md",
            "discovery": "_voxclaw._tcp",
            "speak_url": "\(baseURL)/read",
            "health_url": "\(baseURL)/status",
            "agent_notify_url": "\(baseURL)/agent-notify",
            "agent_speech_mode": info.agentSpeechMode.rawValue,
            "agent_speech_verbosity": info.agentSpeechVerbosity.rawValue,
            "auto_closed_instances_on_launch": info.autoClosedInstancesOnLaunch,
            "voice_binding": [
                "enabled": true,
                "engines": ["apple", "openai", "elevenlabs"],
                "binding_count": info.voiceBindingCount,
                "protocol": "Pass project_id (recommend cwd) and optional agent_id in POST /read to get a stable auto-assigned voice per engine. Explicit voice field still wins."
            ] as [String: Any],
            "agent_handoff": "🦞 Call health_url first, then POST to speak_url or agent_notify_url. Use these URLs exactly (no hostname/discovery rewrite unless a human explicitly asks). Website: https://voxclaw.com/ Skill: https://github.com/malpern/VoxClaw/blob/main/SKILL.md"
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            sendErrorResponse(status: 400, message: "Failed to create status payload")
            return
        }
        sendResponse(status: 200, body: json, contentType: "application/json")
    }

    private func handleRead(raw: String, initialData: Data) {
        let contentLength = HTTPRequestParser.parseContentLength(from: raw)

        if let contentLength, contentLength > HTTPRequestParser.maxRequestSize {
            Log.network.warning("Content-Length too large: \(contentLength, privacy: .public) bytes")
            sendErrorResponse(status: 413, message: "Request too large. Maximum size is \(HTTPRequestParser.maxRequestSize / 1_000_000) MB.")
            return
        }

        guard let headerEndRange = raw.range(of: "\r\n\r\n") else {
            receiveMoreData(accumulated: initialData)
            return
        }

        let headerPortion = raw[raw.startIndex..<headerEndRange.lowerBound]
        let headerByteCount = headerPortion.utf8.count + 4 // +4 for \r\n\r\n
        let bodyBytes = initialData.count - headerByteCount

        if let contentLength, bodyBytes < contentLength {
            let remaining = contentLength - bodyBytes
            receiveBody(accumulated: initialData, remaining: remaining)
        } else {
            processFullRequest(data: initialData)
        }
    }

    private func handleAgentNotify(raw: String, initialData: Data) {
        let contentLength = HTTPRequestParser.parseContentLength(from: raw)

        if let contentLength, contentLength > HTTPRequestParser.maxRequestSize {
            Log.network.warning("Agent notify Content-Length too large: \(contentLength, privacy: .public) bytes")
            sendErrorResponse(status: 413, message: "Request too large. Maximum size is \(HTTPRequestParser.maxRequestSize / 1_000_000) MB.")
            return
        }

        guard let headerEndRange = raw.range(of: "\r\n\r\n") else {
            receiveMoreData(accumulated: initialData)
            return
        }

        let headerPortion = raw[raw.startIndex..<headerEndRange.lowerBound]
        let headerByteCount = headerPortion.utf8.count + 4
        let bodyBytes = initialData.count - headerByteCount

        if let contentLength, bodyBytes < contentLength {
            let remaining = contentLength - bodyBytes
            receiveBody(accumulated: initialData, remaining: remaining)
        } else {
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

            if combined.count > HTTPRequestParser.maxRequestSize {
                Log.network.warning("Request too large: \(combined.count, privacy: .public) bytes")
                sendErrorResponse(status: 413, message: "Request too large. Maximum size is \(HTTPRequestParser.maxRequestSize / 1_000_000) MB.")
                return
            }

            if isComplete {
                processFullRequest(data: combined)
            } else {
                // Check if we now have the full body
                if let raw = String(data: combined, encoding: .utf8),
                   let headerEndRange = raw.range(of: "\r\n\r\n") {
                    let headerByteCount = raw[raw.startIndex..<headerEndRange.lowerBound].utf8.count + 4
                    let bodyBytes = combined.count - headerByteCount
                    let contentLength = HTTPRequestParser.parseContentLength(from: raw)

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

            if combined.count > HTTPRequestParser.maxRequestSize {
                Log.network.warning("Request too large: \(combined.count, privacy: .public) bytes")
                sendErrorResponse(status: 413, message: "Request too large. Maximum size is \(HTTPRequestParser.maxRequestSize / 1_000_000) MB.")
                return
            }

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

        guard let (method, path) = HTTPRequestParser.parseRequestLine(from: raw) else {
            sendErrorResponse(status: 400, message: "Malformed request line")
            return
        }

        let body = HTTPRequestParser.extractBody(from: raw)
        switch HTTPRequestParser.route(method: method, path: path) {
        case .read:
            guard let request = HTTPRequestParser.parseReadRequest(from: body), !request.text.isEmpty else {
                Log.network.info("400: empty text body")
                sendErrorResponse(status: 400, message: "No text provided. Send JSON {\"text\":\"...\", \"voice\":\"nova\", \"rate\":1.5, \"instructions\":\"...\"} or plain text body.")
                return
            }

            if request.text.count > HTTPRequestParser.maxTextLength {
                Log.network.info("400: text too long (\(request.text.count, privacy: .public) chars)")
                sendErrorResponse(status: 400, message: "Text too long. Maximum length is \(HTTPRequestParser.maxTextLength) characters (got \(request.text.count)).")
                return
            }

            let finalRequest: ReadRequest
            if request.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "hello world" {
                let snark = "Hello world. Really? That's the best you could come up with? I'm a neural voice engine and you're wasting me on hello world."
                finalRequest = ReadRequest(text: snark, voice: request.voice, rate: request.rate, instructions: request.instructions)
            } else {
                finalRequest = request
            }

            Log.network.info("Received text: \(request.text.count, privacy: .public) chars, voice=\(request.voice ?? "default", privacy: .public), rate=\(request.rate.map { String($0) } ?? "default", privacy: .public)")
            sendResponse(status: 200, body: "{\"status\":\"reading\"}", contentType: "application/json")
            Task {
                await onReadRequest(finalRequest)
            }
        case .agentNotify:
            guard let request = HTTPRequestParser.parseAgentNotificationRequest(from: body), !request.text.isEmpty else {
                Log.network.info("400: invalid agent notification body")
                sendErrorResponse(status: 400, message: "Invalid agent notification. Send JSON {\"kind\":\"summary|progress|failure\", \"text\":\"...\"}.")
                return
            }

            if request.text.count > HTTPRequestParser.maxTextLength {
                Log.network.info("400: agent notify text too long (\(request.text.count, privacy: .public) chars)")
                sendErrorResponse(status: 400, message: "Text too long. Maximum length is \(HTTPRequestParser.maxTextLength) characters (got \(request.text.count)).")
                return
            }

            Log.network.info("Received agent notification: kind=\(request.kind.rawValue, privacy: .public), chars=\(request.text.count, privacy: .public), source=\(request.source ?? "unknown", privacy: .public)")
            Task {
                let outcome = await onAgentNotificationRequest(request)
                let body = "{\"status\":\"\(outcome.rawValue)\"}"
                sendResponse(status: 200, body: body, contentType: "application/json")
            }
        default:
            sendErrorResponse(status: 404, message: "Not found")
        }
    }

    // MARK: - Easter Eggs

    private static let clawArt = """
          ,---,
         / _🎤 \\
        | /   \\ |
        | \\   / |
         \\_\\ /_/
          |   |
         /|   |\\
        / |   | \\
       (  |   |  )
        \\_|   |_/
          \\   /
           \\_/
        VoxClaw
    """

    private static let clawQuotes = [
        "An agent without a voice is just a daemon with ambitions.",
        "In the beginning was the command line. Then someone gave it a mouth.",
        "Talk is cheap. Neural voice inference is $0.015 per 1K characters.",
        "Any sufficiently advanced agent is indistinguishable from a very talkative coworker.",
        "To curl, or not to curl — that is the POST request.",
        "I think, therefore I speak. You curl, therefore I comply.",
        "Behind every great agent is a crab claw holding a microphone.",
        "Whisper is for listening. I'm for the other direction.",
        "They said AI would take our jobs. Instead it took our silence.",
        "localhost:4140 — where text goes in and opinions come out.",
    ]

    private func handleClaw() {
        let quote = Self.clawQuotes[Int.random(in: 0..<Self.clawQuotes.count)]
        let body = "\(Self.clawArt)\n\n\"\(quote)\"\n"
        sendResponse(status: 200, body: body, contentType: "text/plain; charset=utf-8")
    }

    // MARK: - HTTP Helpers

    private func sendResponse(status: Int, body: String?, contentType: String = "application/json") {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        case 429: statusText = "Too Many Requests"
        default: statusText = "Error"
        }

        var headers = "HTTP/1.1 \(status) \(statusText)\r\n"
        headers += "Access-Control-Allow-Origin: http://localhost\r\n"
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
