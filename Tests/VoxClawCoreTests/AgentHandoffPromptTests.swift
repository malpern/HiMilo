@testable import VoxClawCore
import Testing

struct AgentHandoffPromptTests {

    @Test func promptContainsHealthAndSpeakURLs() {
        let text = AgentHandoffPrompt.make(baseURL: "http://192.168.1.10:4140")
        #expect(text.contains("health_url: http://192.168.1.10:4140/status"))
        #expect(text.contains("speak_url: http://192.168.1.10:4140/read"))
    }

    @Test func promptContainsAgentRules() {
        let text = AgentHandoffPrompt.make(baseURL: "http://localhost:4140")
        #expect(text.contains("GET health_url first"))
        #expect(text.contains("POST text to speak_url"))
    }

    @Test func promptDoesNotContainAgentNotifyURL() {
        let text = AgentHandoffPrompt.make(baseURL: "http://localhost:4140")
        #expect(!text.contains("agent_notify"))
    }

    @Test func promptContainsWebsiteAndSkillDoc() {
        let text = AgentHandoffPrompt.make(baseURL: "http://localhost:4140")
        #expect(text.contains("voxclaw.com"))
        #expect(text.contains("SKILL.md"))
    }
}
