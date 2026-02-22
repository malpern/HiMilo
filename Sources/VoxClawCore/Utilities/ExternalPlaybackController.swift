import Foundation

@MainActor
public protocol ExternalPlaybackControlling {
    func pauseIfPlaying() -> Bool
    func resumePaused()
}

#if os(macOS)
import AppKit

@MainActor
public final class ExternalPlaybackController: ExternalPlaybackControlling {
    private static let mediaApps = ["Music", "Spotify"]
    private var pausedApps: Set<String> = []
    public init() {}

    public func pauseIfPlaying() -> Bool {
        pausedApps.removeAll()
        for app in Self.mediaApps where isPlaying(app) {
            sendCommand("pause", to: app)
            pausedApps.insert(app)
        }
        return !pausedApps.isEmpty
    }

    public func resumePaused() {
        defer { pausedApps.removeAll() }
        for app in pausedApps {
            sendCommand("play", to: app)
        }
    }

    private func isPlaying(_ appName: String) -> Bool {
        runAppleScript("""
        tell application "System Events"
            set appRunning to (name of processes) contains "\(appName)"
        end tell
        if appRunning then
            tell application "\(appName)"
                if player state is playing then
                    return "yes"
                end if
            end tell
        end if
        return "no"
        """) == "yes"
    }

    private func sendCommand(_ command: String, to appName: String) {
        runAppleScript("""
        tell application "\(appName)"
            \(command)
        end tell
        """)
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&errorDict)
        if let errorDict {
            Log.app.error("AppleScript playback control error: \(String(describing: errorDict), privacy: .public)")
            return nil
        }
        return output?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif

#if os(iOS)
@MainActor
public final class ExternalPlaybackController: ExternalPlaybackControlling {
    public init() {}
    public func pauseIfPlaying() -> Bool { false }
    public func resumePaused() {}
}
#endif
