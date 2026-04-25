@testable import VoxClawCore
import Testing
import Foundation

@Suite(.serialized)
struct VoiceAssignerTests {

    private func makeAssigner() -> (VoiceAssigner, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxclaw-voice-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let file = tempDir.appendingPathComponent("bindings.json")
        return (VoiceAssigner(store: VoiceBindingStore(fileURL: file)), file)
    }

    @Test func returnsNilWhenNoProjectId() async {
        let (assigner, _) = makeAssigner()
        let voice = await assigner.resolveVoice(projectId: nil, agentId: nil, engine: .openai)
        #expect(voice == nil)
    }

    @Test func returnsNilWhenProjectIdIsWhitespace() async {
        let (assigner, _) = makeAssigner()
        let voice = await assigner.resolveVoice(projectId: "   ", agentId: nil, engine: .openai)
        #expect(voice == nil)
    }

    @Test func sameIdentityReturnsSameVoice() async {
        let (assigner, _) = makeAssigner()
        let first = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: nil, engine: .openai)
        let second = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: nil, engine: .openai)
        #expect(first != nil)
        #expect(first == second)
    }

    @Test func differentAgentsInSameProjectGetDifferentVoices() async {
        let (assigner, _) = makeAssigner()
        let a = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: "agent-a", engine: .openai)
        let b = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: "agent-b", engine: .openai)
        let c = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: "agent-c", engine: .openai)
        #expect(a != nil && b != nil && c != nil)
        #expect(a != b)
        #expect(b != c)
        #expect(a != c)
    }

    @Test func voicesAreIndependentAcrossEngines() async {
        let (assigner, _) = makeAssigner()
        let openaiVoice = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: nil, engine: .openai)
        let elevenVoice = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: nil, engine: .elevenlabs)
        #expect(openaiVoice != nil)
        #expect(elevenVoice != nil)
        #expect(VoicePool.openAI.contains(openaiVoice!))
        #expect(VoicePool.elevenLabs.contains(elevenVoice!))
    }

    @Test func persistsAcrossAssignerInstances() async {
        let (first, fileURL) = makeAssigner()
        let original = await first.resolveVoice(projectId: "/tmp/persist", agentId: "alpha", engine: .openai)
        #expect(original != nil)

        let reopened = VoiceAssigner(store: VoiceBindingStore(fileURL: fileURL))
        let after = await reopened.resolveVoice(projectId: "/tmp/persist", agentId: "alpha", engine: .openai)
        #expect(after == original)
    }

    @Test func userOverrideSticksAndIsReturned() async {
        let (assigner, _) = makeAssigner()
        await assigner.setUserVoice("shimmer", projectId: "/tmp/proj", agentId: nil, engine: .openai)
        let resolved = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: nil, engine: .openai)
        #expect(resolved == "shimmer")
    }

    @Test func emptyAgentIdIsTreatedAsAbsent() async {
        let (assigner, _) = makeAssigner()
        let withEmpty = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: "", engine: .openai)
        let withNil = await assigner.resolveVoice(projectId: "/tmp/proj", agentId: nil, engine: .openai)
        #expect(withEmpty == withNil)
    }
}
