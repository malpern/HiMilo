@testable import VoxClawCore
import Testing

struct VoicePoolTests {

    @Test func openAIPoolHasMultipleVoices() {
        #expect(VoicePool.openAI.count >= 6)
        #expect(VoicePool.openAI.contains("nova"))
        #expect(VoicePool.openAI.contains("alloy"))
    }

    @Test func openAIPoolHasNoDuplicates() {
        let unique = Set(VoicePool.openAI)
        #expect(unique.count == VoicePool.openAI.count)
    }

    @Test func elevenLabsPoolHasMultipleVoiceIDs() {
        #expect(VoicePool.elevenLabs.count >= 6)
    }

    @Test func elevenLabsPoolHasNoDuplicates() {
        let unique = Set(VoicePool.elevenLabs)
        #expect(unique.count == VoicePool.elevenLabs.count)
    }

    @Test func applePreferredListIsCurated() {
        // The hand-picked list should be non-empty and contain Samantha as a known
        // distinct voice. apple() may filter this further at runtime against
        // installed voices on the host.
        #expect(!VoicePool.applePreferred.isEmpty)
        #expect(VoicePool.applePreferred.contains(where: { $0.contains("Samantha") }))
    }

    @Test func voicesForEngineRoutesToCorrectPool() {
        #expect(VoicePool.voices(for: .openai) == VoicePool.openAI)
        #expect(VoicePool.voices(for: .elevenlabs) == VoicePool.elevenLabs)
        // apple() result depends on the host; assert it's non-empty so we always
        // have at least one voice to assign to a project.
        #expect(!VoicePool.voices(for: .apple).isEmpty)
    }

    @Test func appleReturnsNonEmptyOnHost() {
        // Real macOS hosts always have at least one installed en-* voice.
        // This guards against a regression in the fallback path that would
        // leave the auto-assigner with no voices to pick from.
        #expect(!VoicePool.apple().isEmpty)
    }
}
