import Foundation
import CryptoKit

/// Resolves a voice for a (project_id, agent_id, engine) identity, creating and
/// persisting a deterministic auto-binding on first contact.
///
/// Resolution order:
/// 1. Stored binding for (project_id, agent_id) for the requested engine — whether user-set or auto.
/// 2. Deterministic hash into the engine's pool, with collision avoidance against
///    other entries already bound within the same project. Persisted for future calls.
/// 3. Returns nil if no project_id is supplied (caller uses settings default).
public final class VoiceAssigner: Sendable {
    private let store: VoiceBindingStore

    public init(store: VoiceBindingStore) {
        self.store = store
    }

    public func resolveVoice(
        projectId: String?,
        agentId: String?,
        engine: VoiceEngineType
    ) async -> String? {
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedProjectId, !normalizedProjectId.isEmpty else { return nil }
        let normalizedAgentId = agentId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let existing = await store.binding(projectId: normalizedProjectId, agentId: normalizedAgentId)
        if let voice = existing.voice(for: engine) {
            return voice
        }

        let pool = VoicePool.voices(for: engine)
        guard !pool.isEmpty else { return nil }

        var occupied: Set<String> = []
        if let project = await store.projectBindings(projectId: normalizedProjectId) {
            if let v = project.default.voice(for: engine) { occupied.insert(v) }
            for binding in project.agents.values {
                if let v = binding.voice(for: engine) { occupied.insert(v) }
            }
        }

        let identity = normalizedAgentId.map { "\(normalizedProjectId)\u{0001}\($0)" } ?? normalizedProjectId
        let startIndex = Int(stableHash(identity) % UInt64(pool.count))
        var chosen = pool[startIndex]
        for offset in 0..<pool.count {
            let candidate = pool[(startIndex + offset) % pool.count]
            if !occupied.contains(candidate) {
                chosen = candidate
                break
            }
        }

        var updated = existing
        updated.set(chosen, for: engine, userSet: false)
        await store.setBinding(updated, projectId: normalizedProjectId, agentId: normalizedAgentId)
        return chosen
    }

    /// Explicit user override — persists and marks the binding as user-set.
    public func setUserVoice(
        _ voice: String?,
        projectId: String,
        agentId: String?,
        engine: VoiceEngineType
    ) async {
        var binding = await store.binding(projectId: projectId, agentId: agentId)
        binding.set(voice, for: engine, userSet: true)
        await store.setBinding(binding, projectId: projectId, agentId: agentId)
    }

    public func bindingCount() async -> Int {
        await store.bindingCount()
    }

    private func stableHash(_ string: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(string.utf8))
        var result: UInt64 = 0
        for (i, byte) in digest.prefix(8).enumerated() {
            result |= UInt64(byte) << (8 * i)
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
