@testable import VoxClawCore
import Testing

@MainActor
struct ExternalPlaybackControllerTests {
    @Test func pauseIfPlayingReturnsNil() {
        let controller = ExternalPlaybackController()
        #expect(controller.pauseIfPlaying() == nil)
    }
}
