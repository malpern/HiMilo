@testable import VoxClawCore
import Foundation
import Testing

#if os(macOS)
private struct MockAppleScriptRunner: AppleScriptRunning {
    let responder: (String) -> String?

    func run(_ source: String) -> String? {
        responder(source)
    }
}

@MainActor
struct ExternalPlaybackControllerTests {
    @Test func pauseIfPlayingReturnsNilWhenNoYouTubeTabsArePlaying() {
        let runner = MockAppleScriptRunner { source in
            if source.contains("contains \"Google Chrome\"") || source.contains("contains \"Arc\"") {
                return "true"
            }
            if source.contains("tell application \"Google Chrome\""), source.contains("set outputLines") {
                return "1\t1\thttps://example.com\r1\t2\thttps://www.youtube.com/watch?v=idle"
            }
            if source.contains("tell application \"Arc\""), source.contains("set outputLines") {
                return ""
            }
            if source.contains("execute tab 2 of window 1 javascript"), source.contains("video.readyState < 2") {
                return "paused"
            }
            Issue.record("Unexpected script: \(source)")
            return nil
        }
        let controller = ExternalPlaybackController(scriptRunner: runner)

        let snapshot = controller.pauseIfPlaying()

        #expect(snapshot == nil)
    }

    @Test func pauseIfPlayingCapturesPlayingChromeAndArcTabs() {
        let runner = MockAppleScriptRunner { source in
            if source.contains("contains \"Google Chrome\"") || source.contains("contains \"Arc\"") {
                return "true"
            }
            if source.contains("tell application \"Google Chrome\""), source.contains("set outputLines") {
                return "1\t1\thttps://www.youtube.com/watch?v=chrome\r1\t2\thttps://example.com"
            }
            if source.contains("tell application \"Arc\""), source.contains("set outputLines") {
                return "2\t3\thttps://youtu.be/arc"
            }
            if source.contains("execute tab 1 of window 1 javascript"), source.contains("video.readyState < 2") {
                return "playing"
            }
            if source.contains("execute tab 1 of window 1 javascript"), source.contains("video.pause()") {
                return "paused"
            }
            if source.contains("execute tab 3 of window 2 javascript"), source.contains("video.readyState < 2") {
                return "playing"
            }
            if source.contains("execute tab 3 of window 2 javascript"), source.contains("video.pause()") {
                return "paused"
            }
            Issue.record("Unexpected script: \(source)")
            return nil
        }
        let controller = ExternalPlaybackController(scriptRunner: runner)

        let snapshot = controller.pauseIfPlaying()

        #expect(snapshot?.pausedTabs == [
            PausedBrowserTab(browserName: "Google Chrome", windowIndex: 1, tabIndex: 1, url: "https://www.youtube.com/watch?v=chrome"),
            PausedBrowserTab(browserName: "Arc", windowIndex: 2, tabIndex: 3, url: "https://youtu.be/arc"),
        ])
    }

    @Test func pauseIfPlayingSkipsTabsThatFailToPause() {
        let runner = MockAppleScriptRunner { source in
            if source.contains("contains \"Google Chrome\"") {
                return "true"
            }
            if source.contains("contains \"Arc\"") {
                return "false"
            }
            if source.contains("tell application \"Google Chrome\""), source.contains("set outputLines") {
                return "1\t1\thttps://www.youtube.com/watch?v=chrome"
            }
            if source.contains("execute tab 1 of window 1 javascript"), source.contains("video.readyState < 2") {
                return "playing"
            }
            if source.contains("execute tab 1 of window 1 javascript"), source.contains("video.pause()") {
                return "failed"
            }
            Issue.record("Unexpected script: \(source)")
            return nil
        }
        let controller = ExternalPlaybackController(scriptRunner: runner)

        let snapshot = controller.pauseIfPlaying()

        #expect(snapshot == nil)
    }

    @Test func resumeOnlyTargetsTabsThatStillMatchOriginalURL() {
        var resumedScripts: [String] = []
        let runner = MockAppleScriptRunner { source in
            if source.contains("return URL of tab 1 of window 1") {
                return "https://www.youtube.com/watch?v=same"
            }
            if source.contains("return URL of tab 2 of window 1") {
                return "https://news.ycombinator.com/"
            }
            if source.contains("contains \"Google Chrome\"") {
                return "true"
            }
            if source.contains("execute tab"), source.contains("video.play()") {
                resumedScripts.append(source)
                return "resume-requested"
            }
            Issue.record("Unexpected script: \(source)")
            return nil
        }
        let controller = ExternalPlaybackController(scriptRunner: runner, supportedBrowsers: ["Google Chrome"])
        let snapshot = PlaybackSnapshot(pausedTabs: [
            PausedBrowserTab(browserName: "Google Chrome", windowIndex: 1, tabIndex: 1, url: "https://www.youtube.com/watch?v=same"),
            PausedBrowserTab(browserName: "Google Chrome", windowIndex: 1, tabIndex: 2, url: "https://www.youtube.com/watch?v=other"),
        ])

        controller.resume(snapshot)

        #expect(resumedScripts.count == 1)
        #expect(resumedScripts[0].contains("execute tab 1 of window 1 javascript"))
    }
}
#endif
