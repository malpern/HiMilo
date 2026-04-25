import Foundation

public struct PausedBrowserTab: Sendable, Codable, Equatable {
    public let browserName: String
    public let windowID: Int
    public let tabID: Int
    public let url: String

    public init(browserName: String, windowID: Int, tabID: Int, url: String) {
        self.browserName = browserName
        self.windowID = windowID
        self.tabID = tabID
        self.url = url
    }
}

public struct PlaybackSnapshot: Sendable, Codable, Equatable {
    public let pausedTabs: [PausedBrowserTab]

    public init(pausedTabs: [PausedBrowserTab]) {
        self.pausedTabs = pausedTabs
    }

    public var isEmpty: Bool {
        pausedTabs.isEmpty
    }
}

enum BrowserControlMessageType: String, Codable {
    case registerBrowserBridge = "register_browser_bridge"
    case pauseIfPlaying = "pause_if_playing"
    case pauseResult = "pause_result"
    case resume = "resume"
    case resumeResult = "resume_result"
    case ping
    case pong
    case error
}

struct BrowserControlMessage: Sendable, Codable {
    var id: String
    var type: BrowserControlMessageType
    var snapshot: PlaybackSnapshot?
    var ok: Bool?
    var warning: String?

    init(
        id: String = UUID().uuidString,
        type: BrowserControlMessageType,
        snapshot: PlaybackSnapshot? = nil,
        ok: Bool? = nil,
        warning: String? = nil
    ) {
        self.id = id
        self.type = type
        self.snapshot = snapshot
        self.ok = ok
        self.warning = warning
    }
}

enum BrowserControlRuntime {
    static let servicePort: UInt16 = 4141
    static let hostName = "127.0.0.1"
    static let nativeHostName = "com.malpern.voxclaw"
    static let extensionID = "dhlkfkmalddcliamafnmkhpgennmnbjl"
    static let extensionPublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuLE3z6vi4ihP28kFE6agJdRFkhy7OkfP4kkgn/JC8ysrxow66AnLzhzeQpIYFh7uo8SEd77HBXikcetRYpo6c5V7LeODLzluwMHywLAEYIpbY/OBrlYIJhYzzf2Upjj/LkIkyLGrh832Lu4r8iAWbcjLAxBD9aAVcNG/tfD/3sFYr583bZ5cQJIbTqQ6o1z9uiUn6qnJIz8ZJyyCfvBwMVFOnXQj1PBDWt5YS17kF+GhyIZmXBoXJqXvjS4g7ROQGFjse9ZzTuwn3rGkdMriL5lPyilHHt/13NVfMquCTdVYt0KmxvvKnvzKbMH1Owawat7SJs4vCWSCXLc4SN9rywIDAQAB"
    static let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VoxClaw", isDirectory: true)
    static let extensionInstallDirectory = appSupportDirectory.appendingPathComponent("ChromeExtension", isDirectory: true)
    static let nativeHostScriptURL = appSupportDirectory.appendingPathComponent("voxclaw-browser-host.sh")
}
