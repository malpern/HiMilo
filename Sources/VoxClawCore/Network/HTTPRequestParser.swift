import Foundation

/// Parsed payload from a POST /read request.
public struct ReadRequest: Sendable {
    public let text: String
    public var voice: String?
    public var rate: Float?
    public var instructions: String?
    public var projectId: String?
    public var agentId: String?
    /// True when this request was forwarded from another VoxClaw peer.
    /// Relayed requests are never re-relayed (prevents echo loops).
    public var relayed: Bool

    public init(
        text: String,
        voice: String? = nil,
        rate: Float? = nil,
        instructions: String? = nil,
        projectId: String? = nil,
        agentId: String? = nil,
        relayed: Bool = false
    ) {
        self.text = text
        self.voice = voice
        self.rate = rate
        self.instructions = instructions
        self.projectId = projectId
        self.agentId = agentId
        self.relayed = relayed
    }
}

/// Pure HTTP parsing logic extracted from NetworkSession for testability.
public enum HTTPRequestParser {
    /// Maximum allowed request size (1 MB). Requests exceeding this are rejected with 413.
    static let maxRequestSize = 1_000_000
    /// Maximum allowed text length in characters.
    static let maxTextLength = 50_000

    /// Parsed HTTP route.
    enum Route: Equatable {
        case status
        case read
        case ack
        case control
        case claw
        case corsPreflight
        case notFound(method: String, path: String)
    }

    /// Parses the first line of an HTTP request into method and path.
    /// Returns `nil` if the request line is missing or malformed.
    static func parseRequestLine(from raw: String) -> (method: String, path: String)? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        return (method: String(parts[0]), path: String(parts[1]))
    }

    /// Maps an HTTP method and path to a `Route`.
    static func route(method: String, path: String) -> Route {
        switch (method, path) {
        case ("GET", "/status"):
            return .status
        case ("POST", "/read"):
            return .read
        case ("POST", "/ack"):
            return .ack
        case ("POST", "/control"):
            return .control
        case ("GET", "/claw"):
            return .claw
        case ("OPTIONS", _):
            return .corsPreflight
        default:
            return .notFound(method: method, path: path)
        }
    }

    static func parseContentLength(from raw: String) -> Int? {
        for line in raw.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    static func extractBody(from raw: String) -> String {
        guard let range = raw.range(of: "\r\n\r\n") else { return "" }
        return String(raw[range.upperBound...])
    }

    static func parseReadRequest(from body: String) -> ReadRequest? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try JSON: {"text": "...", "voice": "nova", "rate": 1.5, "instructions": "..."}
        if let jsonData = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let text = json["text"] as? String {
            let voice = json["voice"] as? String
            let rate = (json["rate"] as? NSNumber)?.floatValue
            let instructions = json["instructions"] as? String
            let projectId = (json["project_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let agentId = (json["agent_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let relayed = (json["relayed"] as? Bool) ?? false
            return ReadRequest(
                text: text,
                voice: voice,
                rate: rate,
                instructions: instructions,
                projectId: projectId?.isEmpty == true ? nil : projectId,
                agentId: agentId?.isEmpty == true ? nil : agentId,
                relayed: relayed
            )
        }

        // Fall back to plain text body
        return ReadRequest(text: trimmed)
    }

    public enum ControlAction: String, Sendable {
        case pause
        case resume
        case stop
    }

    public struct ControlRequest: Sendable {
        public let action: ControlAction
        public let origin: String?

        public init(action: ControlAction, origin: String? = nil) {
            self.action = action
            self.origin = origin
        }
    }

    static func parseControlRequest(from body: String) -> ControlRequest? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionRaw = json["action"] as? String,
              let action = ControlAction(rawValue: actionRaw)
        else { return nil }
        let origin = json["origin"] as? String
        return ControlRequest(action: action, origin: origin)
    }

    static func parseAckRequest(from body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projectId = json["project_id"] as? String,
              !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
