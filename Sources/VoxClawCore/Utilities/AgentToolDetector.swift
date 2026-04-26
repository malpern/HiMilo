#if os(macOS)
import Foundation

@MainActor
struct AgentToolDetector {
    enum Tool: String, CaseIterable {
        case claudeCode
        case codex
    }

    struct Status {
        let tool: Tool
        let installed: Bool
        let binaryPath: String?
        let pluginInstalled: Bool
    }

    static func detect() -> [Status] {
        Tool.allCases.map { tool in
            let (installed, path) = checkBinary(tool)
            let pluginInstalled = installed && checkPluginInstalled(tool)
            return Status(tool: tool, installed: installed, binaryPath: path, pluginInstalled: pluginInstalled)
        }
    }

    private static func checkBinary(_ tool: Tool) -> (Bool, String?) {
        let binaryName: String
        let configDir: String
        switch tool {
        case .claudeCode:
            binaryName = "claude"
            configDir = NSHomeDirectory() + "/.claude"
        case .codex:
            binaryName = "codex"
            configDir = NSHomeDirectory() + "/.codex"
        }

        if FileManager.default.fileExists(atPath: configDir) {
            let path = findBinary(binaryName)
            return (true, path)
        }

        if let path = findBinary(binaryName) {
            return (true, path)
        }

        return (false, nil)
    }

    private static func findBinary(_ name: String) -> String? {
        let commonPaths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            NSHomeDirectory() + "/.local/bin/\(name)",
            NSHomeDirectory() + "/.npm-global/bin/\(name)",
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {}
        return nil
    }

    private static func checkPluginInstalled(_ tool: Tool) -> Bool {
        switch tool {
        case .claudeCode:
            let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
            guard let data = FileManager.default.contents(atPath: settingsPath),
                  let content = String(data: data, encoding: .utf8) else { return false }
            return content.contains("voxclaw")
        case .codex:
            let configPath = NSHomeDirectory() + "/.codex/config.toml"
            guard let data = FileManager.default.contents(atPath: configPath),
                  let content = String(data: data, encoding: .utf8) else { return false }
            return content.contains("voxclaw")
        }
    }

    static func installCommand(for tool: Tool) -> String {
        switch tool {
        case .claudeCode:
            return "claude plugin marketplace add malpern/VoxClaw && claude plugin install voxclaw"
        case .codex:
            return "bash -c \"$(curl -fsSL https://raw.githubusercontent.com/malpern/VoxClaw/main/plugins/voxclaw/setup-codex.sh)\""
        }
    }

    static func displayName(for tool: Tool) -> String {
        switch tool {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    static func iconName(for tool: Tool) -> String {
        switch tool {
        case .claudeCode: return "sparkle"
        case .codex: return "terminal"
        }
    }

    static func downloadURL(for tool: Tool) -> URL {
        switch tool {
        case .claudeCode: return URL(string: "https://claude.ai/download")!
        case .codex: return URL(string: "https://github.com/openai/codex")!
        }
    }
}
#endif
