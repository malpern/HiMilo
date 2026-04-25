import Foundation

/// Generates the agent setup pointer text. Single source of truth for the
/// handoff template used in Settings, Onboarding, and peer setup copy.
public enum AgentHandoffPrompt {
    public static func make(baseURL: String) -> String {
        let healthURL = "\(baseURL)/status"
        let speakURL = "\(baseURL)/read"
        return """
        🦞 VoxClaw setup pointer:
        health_url: \(healthURL)
        speak_url: \(speakURL)

        Agent rules:
        1) GET health_url first.
        2) If status is ok, POST text to speak_url.
        3) Use these URLs exactly (no .local/discovery rewrite unless a human explicitly asks).

        Website: https://voxclaw.com/
        Skill doc: https://github.com/malpern/VoxClaw/blob/main/SKILL.md
        """
    }
}
