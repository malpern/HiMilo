import Foundation

/// Sliding-window tracker of which `project_id`s have spoken recently. Used to
/// decide whether the panel should display a project badge — we only badge
/// when ≥2 distinct projects have been active within the window, so single-
/// project use stays uncluttered.
public struct ProjectActivityTracker: Sendable {
    public typealias NowProvider = @Sendable () -> ContinuousClock.Instant

    public let window: Duration
    private let now: NowProvider
    private var entries: [(projectId: String, timestamp: ContinuousClock.Instant)] = []

    public init(
        window: Duration = .seconds(600),
        now: @escaping NowProvider = { ContinuousClock.now }
    ) {
        self.window = window
        self.now = now
    }

    public mutating func record(_ projectId: String) {
        entries.append((projectId, now()))
        prune()
    }

    public func distinctProjectsInWindow() -> Int {
        let cutoff = now() - window
        var seen: Set<String> = []
        for entry in entries where entry.timestamp >= cutoff {
            seen.insert(entry.projectId)
        }
        return seen.count
    }

    /// Number of entries currently retained (post-prune). Exposed for tests.
    public var entryCount: Int { entries.count }

    private mutating func prune() {
        let cutoff = now() - window
        entries.removeAll { $0.timestamp < cutoff }
    }
}
