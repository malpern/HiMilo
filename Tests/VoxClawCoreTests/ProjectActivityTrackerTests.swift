@testable import VoxClawCore
import Testing
import Foundation

struct ProjectActivityTrackerTests {

    /// Mutable clock the tests can drive forward.
    final class FakeClock: @unchecked Sendable {
        private var instant: ContinuousClock.Instant
        init() { self.instant = .now }
        func now() -> ContinuousClock.Instant { instant }
        func advance(_ duration: Duration) { instant = instant.advanced(by: duration) }
    }

    private func makeTracker(window: Duration = .seconds(600)) -> (ProjectActivityTracker, FakeClock) {
        let clock = FakeClock()
        let tracker = ProjectActivityTracker(window: window, now: { [clock] in clock.now() })
        return (tracker, clock)
    }

    @Test func freshTrackerReportsZeroDistinctProjects() {
        let (tracker, _) = makeTracker()
        #expect(tracker.distinctProjectsInWindow() == 0)
    }

    @Test func oneProjectRecordedOnceCountsAsOne() {
        var (tracker, _) = makeTracker()
        tracker.record("alpha")
        #expect(tracker.distinctProjectsInWindow() == 1)
    }

    @Test func sameProjectRecordedTwiceStillCountsAsOne() {
        var (tracker, _) = makeTracker()
        tracker.record("alpha")
        tracker.record("alpha")
        #expect(tracker.distinctProjectsInWindow() == 1)
    }

    @Test func twoDistinctProjectsCountAsTwo() {
        var (tracker, _) = makeTracker()
        tracker.record("alpha")
        tracker.record("beta")
        #expect(tracker.distinctProjectsInWindow() == 2)
    }

    @Test func projectsOutsideWindowDoNotCount() {
        var (tracker, clock) = makeTracker(window: .seconds(600))
        tracker.record("alpha")
        clock.advance(.seconds(601))
        tracker.record("beta")
        // Alpha is older than the window — only beta is in.
        #expect(tracker.distinctProjectsInWindow() == 1)
    }

    @Test func recordingTriggersPruneOfOldEntries() {
        var (tracker, clock) = makeTracker(window: .seconds(600))
        tracker.record("alpha")
        tracker.record("beta")
        clock.advance(.seconds(601))
        tracker.record("gamma")
        // Both alpha + beta fell off the window when gamma was recorded.
        #expect(tracker.entryCount == 1)
        #expect(tracker.distinctProjectsInWindow() == 1)
    }

    @Test func reEnteringWindowAfterGapReturnsTwo() {
        var (tracker, clock) = makeTracker(window: .seconds(600))
        tracker.record("alpha")  // t=0
        clock.advance(.seconds(300))
        tracker.record("beta")   // t=300, alpha still in window
        #expect(tracker.distinctProjectsInWindow() == 2)
    }

    @Test func projectAtBoundaryStillInWindow() {
        var (tracker, clock) = makeTracker(window: .seconds(600))
        tracker.record("alpha")
        clock.advance(.seconds(600)) // exactly at the boundary
        // At exactly the boundary, alpha's timestamp == cutoff. We use >= so
        // it still counts.
        #expect(tracker.distinctProjectsInWindow() == 1)
    }

    @Test func tightWindowDropsEntriesQuickly() {
        var (tracker, clock) = makeTracker(window: .seconds(2))
        tracker.record("alpha")
        clock.advance(.seconds(3))
        tracker.record("beta")
        #expect(tracker.distinctProjectsInWindow() == 1)
    }
}
