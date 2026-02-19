import Foundation
import os

enum AppMode: Sendable {
    case cli(text: String?)
    case menuBar
}

enum ModeDetector {
    static func detect() -> AppMode {
        let args = ProcessInfo.processInfo.arguments
        // args[0] is the executable path, skip it.
        // Filter out macOS-injected arguments (e.g. -NSDocumentRevisionsDebugMode, -psn_*).
        let userArgs = Array(args.dropFirst().filter { !$0.hasPrefix("-NS") && !$0.hasPrefix("-psn") })

        Log.app.debug("ModeDetector: argCount=\(args.count, privacy: .public), userArgs=\(userArgs.count, privacy: .public), isApp=\(isRunningAsApp, privacy: .public), isatty=\(isatty(STDIN_FILENO), privacy: .public)")

        let result = detect(
            userArgs: userArgs,
            isRunningAsApp: isRunningAsApp,
            isStdinTTY: isatty(STDIN_FILENO) != 0
        )

        Log.app.debug("ModeDetector → \(String(describing: result), privacy: .public)")
        return result
    }

    /// Testable overload with injected inputs
    static func detect(userArgs: [String], isRunningAsApp: Bool, isStdinTTY: Bool) -> AppMode {
        // If there are CLI arguments (beyond the executable), it's CLI mode
        if !userArgs.isEmpty {
            return .cli(text: nil)
        }

        // When launched inside a .app bundle (Finder, open, launchd), stdin is
        // not a tty but that doesn't mean data is piped. Go straight to menu bar.
        if isRunningAsApp {
            return .menuBar
        }

        // Terminal launch with piped stdin → CLI mode
        if !isStdinTTY {
            return .cli(text: nil)
        }

        // No args, no piped input → menu bar mode
        return .menuBar
    }

    private static var isRunningAsApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }
}
