import Foundation

public struct PausedBrowserTab: Sendable, Equatable {
    public let browserName: String
    public let windowIndex: Int
    public let tabIndex: Int
    public let url: String

    public init(browserName: String, windowIndex: Int, tabIndex: Int, url: String) {
        self.browserName = browserName
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.url = url
    }
}

public struct PlaybackSnapshot: Sendable, Equatable {
    public let pausedTabs: [PausedBrowserTab]

    public init(pausedTabs: [PausedBrowserTab]) {
        self.pausedTabs = pausedTabs
    }

    public var isEmpty: Bool {
        pausedTabs.isEmpty
    }
}

@MainActor
public protocol ExternalPlaybackControlling {
    func pauseIfPlaying() -> PlaybackSnapshot?
    func resume(_ snapshot: PlaybackSnapshot)
}

#if os(macOS)
import AppKit

private struct BrowserTabCandidate: Equatable {
    let browserName: String
    let windowIndex: Int
    let tabIndex: Int
    let url: String
}

protocol AppleScriptRunning {
    func run(_ source: String) -> String?
}

private struct SystemAppleScriptRunner: AppleScriptRunning {
    func run(_ source: String) -> String? {
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&errorDict)
        if let errorDict {
            Log.playback.error("AppleScript playback control error: \(String(describing: errorDict), privacy: .public)")
            return nil
        }
        return output?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
public final class ExternalPlaybackController: ExternalPlaybackControlling {
    private static let supportedBrowsers = ["Google Chrome", "Arc"]

    private let scriptRunner: any AppleScriptRunning
    private let supportedBrowsersOverride: [String]

    public init() {
        self.scriptRunner = SystemAppleScriptRunner()
        self.supportedBrowsersOverride = Self.supportedBrowsers
    }

    init(scriptRunner: any AppleScriptRunning, supportedBrowsers: [String]? = nil) {
        self.scriptRunner = scriptRunner
        self.supportedBrowsersOverride = supportedBrowsers ?? Self.supportedBrowsers
    }

    public func pauseIfPlaying() -> PlaybackSnapshot? {
        var pausedTabs: [PausedBrowserTab] = []

        for browserName in supportedBrowsersOverride {
            let candidates = enumerateTabs(for: browserName).filter { isYouTubeURL($0.url) }
            if !candidates.isEmpty {
                Log.playback.info("Playback scan: \(browserName, privacy: .public) yielded \(candidates.count, privacy: .public) YouTube candidate tabs")
            }

            for candidate in candidates where isActivelyPlaying(candidate) {
                if pause(candidate) {
                    pausedTabs.append(
                        PausedBrowserTab(
                            browserName: candidate.browserName,
                            windowIndex: candidate.windowIndex,
                            tabIndex: candidate.tabIndex,
                            url: candidate.url
                        )
                    )
                }
            }
        }

        guard !pausedTabs.isEmpty else {
            Log.playback.info("Playback scan found no active Chrome-family YouTube tabs to pause")
            return nil
        }

        Log.playback.info("Paused \(pausedTabs.count, privacy: .public) browser tabs before speech")
        return PlaybackSnapshot(pausedTabs: pausedTabs)
    }

    public func resume(_ snapshot: PlaybackSnapshot) {
        assert(!snapshot.isEmpty, "Empty playback snapshots must not be resumed")

        guard !snapshot.isEmpty else { return }

        for pausedTab in snapshot.pausedTabs {
            guard let currentURL = urlForTab(
                browserName: pausedTab.browserName,
                windowIndex: pausedTab.windowIndex,
                tabIndex: pausedTab.tabIndex
            ) else {
                Log.playback.info("Skipping resume for missing tab \(pausedTab.browserName, privacy: .public) w\(pausedTab.windowIndex, privacy: .public) t\(pausedTab.tabIndex, privacy: .public)")
                continue
            }

            guard currentURL == pausedTab.url, isYouTubeURL(currentURL) else {
                Log.playback.info("Skipping resume for navigated tab \(pausedTab.browserName, privacy: .public) w\(pausedTab.windowIndex, privacy: .public) t\(pausedTab.tabIndex, privacy: .public)")
                continue
            }

            if resumePlayback(for: pausedTab) {
                Log.playback.info("Resumed tab \(pausedTab.browserName, privacy: .public) w\(pausedTab.windowIndex, privacy: .public) t\(pausedTab.tabIndex, privacy: .public)")
            }
        }
    }

    private func enumerateTabs(for browserName: String) -> [BrowserTabCandidate] {
        guard isRunning(browserName) else { return [] }

        let script = """
        tell application "\(escapeAppleScript(browserName))"
            set outputLines to {}
            repeat with windowIndex from 1 to count of windows
                repeat with tabIndex from 1 to count of tabs of window windowIndex
                    try
                        set tabURL to URL of tab tabIndex of window windowIndex
                        if tabURL is not missing value then
                            set end of outputLines to (windowIndex as text) & tab & (tabIndex as text) & tab & tabURL
                        end if
                    end try
                end repeat
            end repeat
            return outputLines as text
        end tell
        """

        guard let raw = scriptRunner.run(script), !raw.isEmpty else { return [] }

        return raw
            .split(separator: "\r", omittingEmptySubsequences: true)
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 3,
                      let windowIndex = Int(parts[0]),
                      let tabIndex = Int(parts[1]) else {
                    return nil
                }
                let url = String(parts[2])
                return BrowserTabCandidate(
                    browserName: browserName,
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    url: url
                )
            }
    }

    private func isRunning(_ browserName: String) -> Bool {
        let script = """
        tell application "System Events"
            return ((name of processes) contains "\(escapeAppleScript(browserName))") as text
        end tell
        """
        return normalizeBoolean(scriptRunner.run(script))
    }

    private func isActivelyPlaying(_ candidate: BrowserTabCandidate) -> Bool {
        let result = executeJavaScript(
            """
            (() => {
                const video = document.querySelector('video');
                if (!video) return 'missing';
                if (video.ended) return 'ended';
                if (video.paused) return 'paused';
                if (video.readyState < 2) return 'buffering';
                return 'playing';
            })();
            """,
            in: candidate
        )
        let isPlaying = result == "playing"
        Log.playback.info("Playback check: \(candidate.browserName, privacy: .public) w\(candidate.windowIndex, privacy: .public) t\(candidate.tabIndex, privacy: .public) -> \(result ?? "nil", privacy: .public)")
        return isPlaying
    }

    private func pause(_ candidate: BrowserTabCandidate) -> Bool {
        let result = executeJavaScript(
            """
            (() => {
                const video = document.querySelector('video');
                if (!video) return 'missing';
                if (video.ended) return 'ended';
                if (video.paused) return 'already-paused';
                video.pause();
                return video.paused ? 'paused' : 'failed';
            })();
            """,
            in: candidate
        )
        let didPause = result == "paused"
        if !didPause {
            Log.playback.info("Pause skipped: \(candidate.browserName, privacy: .public) w\(candidate.windowIndex, privacy: .public) t\(candidate.tabIndex, privacy: .public) -> \(result ?? "nil", privacy: .public)")
        }
        return didPause
    }

    private func resumePlayback(for pausedTab: PausedBrowserTab) -> Bool {
        let candidate = BrowserTabCandidate(
            browserName: pausedTab.browserName,
            windowIndex: pausedTab.windowIndex,
            tabIndex: pausedTab.tabIndex,
            url: pausedTab.url
        )
        let result = executeJavaScript(
            """
            (() => {
                const video = document.querySelector('video');
                if (!video) return 'missing';
                if (video.ended) return 'ended';
                if (!video.paused) return 'already-playing';
                video.play();
                return 'resume-requested';
            })();
            """,
            in: candidate
        )
        return result == "resume-requested" || result == "already-playing"
    }

    private func urlForTab(browserName: String, windowIndex: Int, tabIndex: Int) -> String? {
        guard isRunning(browserName) else { return nil }

        let script = """
        tell application "\(escapeAppleScript(browserName))"
            try
                return URL of tab \(tabIndex) of window \(windowIndex)
            on error
                return ""
            end try
        end tell
        """

        guard let result = scriptRunner.run(script), !result.isEmpty else {
            return nil
        }
        return result
    }

    private func executeJavaScript(_ javascript: String, in candidate: BrowserTabCandidate) -> String? {
        let script = """
        tell application "\(escapeAppleScript(candidate.browserName))"
            try
                return execute tab \(candidate.tabIndex) of window \(candidate.windowIndex) javascript "\(escapeJavaScriptForAppleScript(javascript))"
            on error
                return ""
            end try
        end tell
        """
        return scriptRunner.run(script)
    }

    private func isYouTubeURL(_ urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString),
              let host = components.host?.lowercased() else {
            return false
        }
        return host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
    }

    private func normalizeBoolean(_ text: String?) -> Bool {
        guard let text else { return false }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes":
            return true
        default:
            return false
        }
    }

    private func escapeAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func escapeJavaScriptForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
#endif

#if os(iOS)
@MainActor
public final class ExternalPlaybackController: ExternalPlaybackControlling {
    public init() {}
    public func pauseIfPlaying() -> PlaybackSnapshot? { nil }
    public func resume(_ snapshot: PlaybackSnapshot) {}
}
#endif
