@testable import HiMiloCore
import Testing

struct ModeDetectorTests {
    @Test func cliModeWhenUserArgsPresent() {
        let mode = ModeDetector.detect(userArgs: ["--verbose", "hello"], isRunningAsApp: false, isStdinTTY: true)
        guard case .cli = mode else {
            Issue.record("Expected .cli, got \(mode)")
            return
        }
    }

    @Test func menuBarModeWhenRunningAsApp() {
        let mode = ModeDetector.detect(userArgs: [], isRunningAsApp: true, isStdinTTY: false)
        guard case .menuBar = mode else {
            Issue.record("Expected .menuBar, got \(mode)")
            return
        }
    }

    @Test func cliModeWhenStdinIsPiped() {
        let mode = ModeDetector.detect(userArgs: [], isRunningAsApp: false, isStdinTTY: false)
        guard case .cli = mode else {
            Issue.record("Expected .cli, got \(mode)")
            return
        }
    }

    @Test func menuBarModeWhenNoArgsNoAppNoStdin() {
        let mode = ModeDetector.detect(userArgs: [], isRunningAsApp: false, isStdinTTY: true)
        guard case .menuBar = mode else {
            Issue.record("Expected .menuBar, got \(mode)")
            return
        }
    }

    @Test func cliArgsTakePriorityOverAppBundle() {
        let mode = ModeDetector.detect(userArgs: ["--listen"], isRunningAsApp: true, isStdinTTY: true)
        guard case .cli = mode else {
            Issue.record("Expected .cli, got \(mode)")
            return
        }
    }

    @Test func appBundleTakesPriorityOverPipedStdin() {
        let mode = ModeDetector.detect(userArgs: [], isRunningAsApp: true, isStdinTTY: false)
        guard case .menuBar = mode else {
            Issue.record("Expected .menuBar, got \(mode)")
            return
        }
    }
}
