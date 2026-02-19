import AppKit
import Foundation
import os

enum InputResolver {
    static func resolve(positional: [String], clipboardFlag: Bool, filePath: String?) throws -> String {
        // Priority: file > clipboard > stdin > positional args
        if let path = filePath {
            let text = try readFile(at: path)
            Log.input.info("Resolved from file (\(text.count, privacy: .public) chars)")
            return text
        }

        if clipboardFlag {
            let text = try readClipboard()
            Log.input.info("Resolved from clipboard (\(text.count, privacy: .public) chars)")
            return text
        }

        if let piped = readStdin() {
            Log.input.info("Resolved from stdin (\(piped.count, privacy: .public) chars)")
            return piped
        }

        if !positional.isEmpty {
            let text = positional.joined(separator: " ")
            Log.input.info("Resolved from positional args (\(text.count, privacy: .public) chars)")
            return text
        }

        Log.input.debug("No input resolved")
        return ""
    }

    static func readFile(at path: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func readClipboard() throws -> String {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            throw InputError.emptyClipboard
        }
        return text
    }

    private static func readStdin() -> String? {
        guard !isatty(STDIN_FILENO).boolValue else { return nil }
        var lines: [String] = []
        while let line = readLine(strippingNewline: false) {
            lines.append(line)
        }
        let result = lines.joined()
        return result.isEmpty ? nil : result
    }

    enum InputError: Error, CustomStringConvertible {
        case emptyClipboard
        case fileNotFound(String)

        var description: String {
            switch self {
            case .emptyClipboard:
                return "Clipboard is empty"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            }
        }
    }
}

private extension Int32 {
    var boolValue: Bool { self != 0 }
}
