import AVFoundation
@testable import VoxClawCore
import Testing

struct OnboardingResourceTests {
    @Test func onboardingOpenAIMp3ExistsInBundle() throws {
        let url = Bundle.module.url(forResource: "onboarding-openai", withExtension: "mp3")
        #expect(url != nil, "onboarding-openai.mp3 must be present in the resource bundle")
    }

    @Test func onboardingOpenAIMp3IsPlayable() throws {
        let url = try #require(Bundle.module.url(forResource: "onboarding-openai", withExtension: "mp3"))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 0, "MP3 must have non-zero duration")
    }

    @Test func onboardingOpenAIMp3HasReasonableSize() throws {
        let url = try #require(Bundle.module.url(forResource: "onboarding-openai", withExtension: "mp3"))
        let data = try Data(contentsOf: url)
        // A real voice recording should be at least 10KB
        #expect(data.count > 10_000, "MP3 should be a real recording, not a stub (\(data.count) bytes)")
    }
}
