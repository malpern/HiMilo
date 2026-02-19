@testable import VoxClawCore
import Foundation
import Testing

struct InputResolverTests {
    @Test func resolvePositionalArgs() throws {
        let result = try InputResolver.resolve(positional: ["hello", "world"], clipboardFlag: false, filePath: nil)
        #expect(result == "hello world")
    }

    @Test func resolveEmptyPositional() throws {
        let result = try InputResolver.resolve(positional: [], clipboardFlag: false, filePath: nil)
        #expect(result == "")
    }

    @Test func resolveSinglePositional() throws {
        let result = try InputResolver.resolve(positional: ["hello"], clipboardFlag: false, filePath: nil)
        #expect(result == "hello")
    }

    @Test func resolveFromFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let filePath = tempDir.appendingPathComponent("voxclaw-test-\(UUID().uuidString).txt")
        try "file content here".write(to: filePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: filePath) }

        let result = try InputResolver.resolve(positional: [], clipboardFlag: false, filePath: filePath.path)
        #expect(result == "file content here")
    }

    @Test func resolveFileTakesPriorityOverPositional() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let filePath = tempDir.appendingPathComponent("voxclaw-test-\(UUID().uuidString).txt")
        try "from file".write(to: filePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: filePath) }

        let result = try InputResolver.resolve(positional: ["from", "args"], clipboardFlag: false, filePath: filePath.path)
        #expect(result == "from file")
    }

    @Test func resolveNonexistentFileThrows() {
        #expect(throws: (any Error).self) {
            try InputResolver.resolve(positional: [], clipboardFlag: false, filePath: "/nonexistent/path.txt")
        }
    }
}
