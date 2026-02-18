import AppKit
import Foundation

enum InputResolver {
    static func resolve(positional: [String], clipboardFlag: Bool, filePath: String?) throws -> String {
        // Priority: file > clipboard > stdin > positional args
        if let path = filePath {
            return try readFile(at: path)
        }

        if clipboardFlag {
            return try readClipboard()
        }

        if let piped = readStdin() {
            return piped
        }

        if !positional.isEmpty {
            return positional.joined(separator: " ")
        }

        return ""
    }

    private static func readFile(at path: String) throws -> String {
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
