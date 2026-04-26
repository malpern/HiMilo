@testable import VoxClawCore
import Testing
import Foundation

@Suite(.serialized)
struct VoiceBindingStoreTests {

    private func makeStore() -> (VoiceBindingStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxclaw-store-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let file = tempDir.appendingPathComponent("bindings.json")
        return (VoiceBindingStore(fileURL: file), file)
    }

    @Test func loadReturnsEmptyWhenFileMissing() async {
        let (store, _) = makeStore()
        let file = await store.load()
        #expect(file.projects.isEmpty)
        #expect(file.version == 1)
    }

    @Test func setAndGetBindingForDefault() async {
        let (store, _) = makeStore()
        var binding = VoiceBinding()
        binding.set("nova", for: .openai, userSet: false)
        await store.setBinding(binding, projectId: "/tmp/a", agentId: nil)

        let loaded = await store.binding(projectId: "/tmp/a", agentId: nil)
        #expect(loaded.openai == "nova")
    }

    @Test func setAndGetBindingForAgent() async {
        let (store, _) = makeStore()
        var binding = VoiceBinding()
        binding.set("onyx", for: .openai, userSet: true)
        await store.setBinding(binding, projectId: "/tmp/a", agentId: "worker")

        let loaded = await store.binding(projectId: "/tmp/a", agentId: "worker")
        #expect(loaded.openai == "onyx")
        #expect(loaded.isUserSet(for: .openai))
    }

    @Test func persistsToDisk() async {
        let (store, fileURL) = makeStore()
        var binding = VoiceBinding()
        binding.set("alloy", for: .openai, userSet: false)
        await store.setBinding(binding, projectId: "/tmp/persist", agentId: nil)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let reopened = VoiceBindingStore(fileURL: fileURL)
        let loaded = await reopened.binding(projectId: "/tmp/persist", agentId: nil)
        #expect(loaded.openai == "alloy")
    }

    @Test func corruptFileBacksUpAndReturnsEmpty() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxclaw-store-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let file = tempDir.appendingPathComponent("bindings.json")
        try? "not valid json{{{".write(to: file, atomically: true, encoding: .utf8)

        let store = VoiceBindingStore(fileURL: file)
        let result = await store.load()
        #expect(result.projects.isEmpty)

        let backup = file.appendingPathExtension("bak")
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func bindingCountTallies() async {
        let (store, _) = makeStore()
        var b = VoiceBinding()
        b.set("nova", for: .openai, userSet: false)
        await store.setBinding(b, projectId: "/tmp/a", agentId: nil)
        await store.setBinding(b, projectId: "/tmp/a", agentId: "alpha")
        await store.setBinding(b, projectId: "/tmp/b", agentId: nil)

        let count = await store.bindingCount()
        #expect(count == 3)
    }
}
