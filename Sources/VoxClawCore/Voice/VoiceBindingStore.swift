import Foundation
import os

public struct VoiceBinding: Codable, Sendable, Equatable {
    public var apple: String?
    public var openai: String?
    public var elevenlabs: String?
    /// Engines whose voice was explicitly set by the user; those are sticky and
    /// never overwritten by auto-assignment.
    public var userSetEngines: Set<String>

    public init(
        apple: String? = nil,
        openai: String? = nil,
        elevenlabs: String? = nil,
        userSetEngines: Set<String> = []
    ) {
        self.apple = apple
        self.openai = openai
        self.elevenlabs = elevenlabs
        self.userSetEngines = userSetEngines
    }

    public func voice(for engine: VoiceEngineType) -> String? {
        switch engine {
        case .apple: return apple
        case .openai: return openai
        case .elevenlabs: return elevenlabs
        }
    }

    public mutating func set(_ voice: String?, for engine: VoiceEngineType, userSet: Bool) {
        switch engine {
        case .apple: apple = voice
        case .openai: openai = voice
        case .elevenlabs: elevenlabs = voice
        }
        if userSet {
            userSetEngines.insert(engine.rawValue)
        } else {
            userSetEngines.remove(engine.rawValue)
        }
    }

    public func isUserSet(for engine: VoiceEngineType) -> Bool {
        userSetEngines.contains(engine.rawValue)
    }
}

public struct ProjectBindings: Codable, Sendable, Equatable {
    public var `default`: VoiceBinding
    public var agents: [String: VoiceBinding]

    public init(default defaultBinding: VoiceBinding = VoiceBinding(), agents: [String: VoiceBinding] = [:]) {
        self.default = defaultBinding
        self.agents = agents
    }
}

public struct VoiceBindingsFile: Codable, Sendable, Equatable {
    public var version: Int
    public var projects: [String: ProjectBindings]

    public init(version: Int = 1, projects: [String: ProjectBindings] = [:]) {
        self.version = version
        self.projects = projects
    }
}

public actor VoiceBindingStore {
    private let fileURL: URL
    private var cache: VoiceBindingsFile?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        return base
            .appendingPathComponent("VoxClaw", isDirectory: true)
            .appendingPathComponent("voice-bindings.json")
    }

    @discardableResult
    public func load() -> VoiceBindingsFile {
        if let cache { return cache }
        let result: VoiceBindingsFile
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                result = try JSONDecoder().decode(VoiceBindingsFile.self, from: data)
            } catch {
                Log.settings.warning("Voice bindings file is corrupted, backing up: \(error, privacy: .public)")
                let backup = fileURL.appendingPathExtension("bak")
                try? fm.removeItem(at: backup)
                try? fm.copyItem(at: fileURL, to: backup)
                result = VoiceBindingsFile()
            }
        } else {
            result = VoiceBindingsFile()
        }
        cache = result
        return result
    }

    public func binding(projectId: String, agentId: String?) -> VoiceBinding {
        let file = load()
        guard let project = file.projects[projectId] else { return VoiceBinding() }
        if let agentId, let agentBinding = project.agents[agentId] {
            return agentBinding
        }
        return project.default
    }

    public func projectBindings(projectId: String) -> ProjectBindings? {
        load().projects[projectId]
    }

    public func setBinding(_ binding: VoiceBinding, projectId: String, agentId: String?) {
        var file = load()
        var project = file.projects[projectId] ?? ProjectBindings()
        if let agentId {
            project.agents[agentId] = binding
        } else {
            project.default = binding
        }
        file.projects[projectId] = project
        cache = file
        save(file)
    }

    public func removeBinding(projectId: String, agentId: String?) {
        var file = load()
        guard var project = file.projects[projectId] else { return }
        if let agentId {
            project.agents.removeValue(forKey: agentId)
        } else {
            project.default = VoiceBinding()
        }
        if project.agents.isEmpty && project.default == VoiceBinding() {
            file.projects.removeValue(forKey: projectId)
        } else {
            file.projects[projectId] = project
        }
        cache = file
        save(file)
    }

    public func allBindings() -> VoiceBindingsFile {
        load()
    }

    public func bindingCount() -> Int {
        let file = load()
        return file.projects.values.reduce(0) { $0 + 1 + $1.agents.count }
    }

    private func save(_ file: VoiceBindingsFile) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            Log.settings.error("Failed to save voice bindings: \(error, privacy: .public)")
        }
    }
}
