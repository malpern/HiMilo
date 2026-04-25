import Foundation

public enum AgentSpeechMode: String, CaseIterable, Codable, Sendable {
    case off
    case summary
    case live

    public var displayName: String {
        switch self {
        case .off:
            "Off"
        case .summary:
            "Final Summaries"
        case .live:
            "Live Updates"
        }
    }

    public func allows(_ kind: AgentNotificationKind) -> Bool {
        switch self {
        case .off:
            return false
        case .summary:
            return kind != .progress
        case .live:
            return true
        }
    }
}

public enum AgentSpeechVerbosity: String, CaseIterable, Codable, Sendable {
    case brief
    case normal

    public var displayName: String {
        switch self {
        case .brief:
            "Brief"
        case .normal:
            "Normal"
        }
    }
}

public enum AgentNotificationKind: String, CaseIterable, Codable, Sendable {
    case summary
    case progress
    case failure
}

public struct AgentNotificationRequest: Sendable {
    public let kind: AgentNotificationKind
    public let text: String
    public var source: String?
    public var voice: String?
    public var rate: Float?
    public var instructions: String?
    public var modeOverride: AgentSpeechMode?
    public var projectId: String?
    public var agentId: String?

    public init(
        kind: AgentNotificationKind,
        text: String,
        source: String? = nil,
        voice: String? = nil,
        rate: Float? = nil,
        instructions: String? = nil,
        modeOverride: AgentSpeechMode? = nil,
        projectId: String? = nil,
        agentId: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.source = source
        self.voice = voice
        self.rate = rate
        self.instructions = instructions
        self.modeOverride = modeOverride
        self.projectId = projectId
        self.agentId = agentId
    }

    public func shouldSpeak(currentMode: AgentSpeechMode) -> Bool {
        (modeOverride ?? currentMode).allows(kind)
    }

    public func spokenText(verbosity: AgentSpeechVerbosity) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard verbosity == .brief else { return trimmed }

        let sentenceCount: Int = kind == .summary ? 2 : 1
        let shortened = trimmed.prefixSentences(sentenceCount)
        if shortened.isEmpty {
            return String(trimmed.prefix(160))
        }
        return shortened
    }
}

public enum AgentNotificationOutcome: String, Sendable {
    case reading
    case suppressed
}

private extension String {
    func prefixSentences(_ count: Int) -> String {
        guard count > 0 else { return "" }

        let endPunctuation = CharacterSet(charactersIn: ".!?")
        var sentences: [String] = []
        var current = ""

        for scalar in unicodeScalars {
            current.unicodeScalars.append(scalar)
            if endPunctuation.contains(scalar), !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                if sentences.count == count {
                    break
                }
            }
        }

        if sentences.count < count, !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return sentences.joined(separator: " ")
    }
}
