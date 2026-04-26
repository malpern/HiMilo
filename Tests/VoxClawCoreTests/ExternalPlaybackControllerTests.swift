@testable import VoxClawCore
import Foundation
import Testing

#if os(macOS)
private struct MockBrowserControlBridge: BrowserControlBridging {
    var pauseResponse: BrowserControlMessage
    var resumeResponse: BrowserControlMessage = BrowserControlMessage(type: .resumeResult, ok: true)
    var resumedSnapshots: LockedSnapshots = LockedSnapshots()

    func pauseIfPlaying() -> BrowserControlMessage {
        pauseResponse
    }

    func resume(_ snapshot: PlaybackSnapshot) -> BrowserControlMessage {
        resumedSnapshots.append(snapshot)
        return resumeResponse
    }
}

private final class LockedSnapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [PlaybackSnapshot] = []

    func append(_ snapshot: PlaybackSnapshot) {
        lock.lock()
        value.append(snapshot)
        lock.unlock()
    }

    func read() -> [PlaybackSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
struct ExternalPlaybackControllerTests {
    @Test func pauseIfPlayingReturnsSnapshotFromBridge() {
        let snapshot = PlaybackSnapshot(pausedTabs: [
            PausedBrowserTab(browserName: "Google Chrome Canary", windowID: 1, tabID: 33, url: "https://www.youtube.com/watch?v=abc")
        ])
        let controller = ExternalPlaybackController(
            bridge: MockBrowserControlBridge(
                pauseResponse: BrowserControlMessage(type: .pauseResult, snapshot: snapshot)
            )
        )

        let result = controller.pauseIfPlaying()

        #expect(result == snapshot)
        #expect(SharedApp.appState.browserControlWarning == nil)
    }

    @Test func pauseIfPlayingPublishesWarningsFromBridge() {
        let controller = ExternalPlaybackController(
            bridge: MockBrowserControlBridge(
                pauseResponse: BrowserControlMessage(
                    type: .error,
                    ok: false,
                    warning: "Load the VoxClaw browser extension in Chrome or Chrome Canary."
                )
            )
        )

        let result = controller.pauseIfPlaying()

        #expect(result == nil)
        #expect(SharedApp.appState.browserControlWarning == "Load the VoxClaw browser extension in Chrome or Chrome Canary.")
    }

    @Test func resumeForwardsSnapshotToBridge() {
        let snapshot = PlaybackSnapshot(pausedTabs: [
            PausedBrowserTab(browserName: "Google Chrome Canary", windowID: 2, tabID: 1, url: "https://www.youtube.com/watch?v=resume")
        ])
        let bridge = MockBrowserControlBridge(
            pauseResponse: BrowserControlMessage(type: .pauseResult, snapshot: nil)
        )
        let controller = ExternalPlaybackController(bridge: bridge)

        controller.resume(snapshot)

        #expect(bridge.resumedSnapshots.read() == [snapshot])
    }
}
#endif
