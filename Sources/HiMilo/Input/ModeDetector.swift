import Foundation

enum AppMode: Sendable {
    case cli(text: String?)
    case menuBar
}

enum ModeDetector {
    static func detect() -> AppMode {
        let args = ProcessInfo.processInfo.arguments
        // args[0] is the executable path, skip it
        let userArgs = Array(args.dropFirst())

        // If there are CLI arguments (beyond the executable), it's CLI mode
        if !userArgs.isEmpty {
            return .cli(text: nil) // CLIParser will handle actual parsing
        }

        // If stdin has piped data, it's CLI mode
        if !isatty(STDIN_FILENO).boolValue {
            return .cli(text: nil)
        }

        // No args, no piped input -> menu bar mode
        return .menuBar
    }

    private static var isStdinPiped: Bool {
        !isatty(STDIN_FILENO).boolValue
    }
}

private extension Int32 {
    var boolValue: Bool { self != 0 }
}
