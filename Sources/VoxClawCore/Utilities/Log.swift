import Foundation
import Synchronization
import os

enum Log {
    static let subsystem = "com.malpern.voxclaw"
    static let app      = Logger(subsystem: subsystem, category: "app")
    static let cli      = Logger(subsystem: subsystem, category: "cli")
    static let input    = Logger(subsystem: subsystem, category: "input")
    static let tts      = Logger(subsystem: subsystem, category: "tts")
    static let audio    = Logger(subsystem: subsystem, category: "audio")
    static let session  = Logger(subsystem: subsystem, category: "session")
    static let network  = Logger(subsystem: subsystem, category: "network")
    static let panel    = Logger(subsystem: subsystem, category: "panel")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let settings    = Logger(subsystem: subsystem, category: "settings")
    static let onboarding  = Logger(subsystem: subsystem, category: "onboarding")

    private static let _isVerbose = Mutex(false)
    static var isVerbose: Bool {
        get { _isVerbose.withLock { $0 } }
        set { _isVerbose.withLock { $0 = newValue } }
    }

    /// Echo to stderr when --verbose is active
    static func verbose(_ message: String) {
        guard isVerbose else { return }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
