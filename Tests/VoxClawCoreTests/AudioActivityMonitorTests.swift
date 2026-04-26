#if os(macOS) && !APPSTORE
@testable import VoxClawCore
import CoreAudio
import Testing

/// Hand-rolled CoreAudio probe used to exercise AudioActivityMonitor without
/// touching real CoreAudio.
struct FakeCoreAudioProbe: CoreAudioProbe {
    struct Process {
        let id: AudioObjectID
        var pid: pid_t?
        var bundleID: String?
        var runningOutput: Bool
        var runningInput: Bool
    }

    let processes: [Process]

    func processObjects() -> [AudioObjectID] { processes.map(\.id) }
    func bundleID(for processID: AudioObjectID) -> String? {
        processes.first(where: { $0.id == processID })?.bundleID
    }
    func pid(for processID: AudioObjectID) -> pid_t? {
        processes.first(where: { $0.id == processID })?.pid
    }
    func isRunningOutput(processID: AudioObjectID) -> Bool {
        processes.first(where: { $0.id == processID })?.runningOutput ?? false
    }
    func isRunningInput(processID: AudioObjectID) -> Bool {
        processes.first(where: { $0.id == processID })?.runningInput ?? false
    }
}

struct AudioActivityMonitorTests {

    // MARK: - activeDeferListBundleIDs

    @Test func activeDeferList_emptyWhenNoProcesses() {
        let probe = FakeCoreAudioProbe(processes: [])
        #expect(AudioActivityMonitor.activeDeferListBundleIDs(probe: probe).isEmpty)
    }

    @Test func activeDeferList_emptyWhenNobodyOutputting() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "us.zoom.xos", runningOutput: false, runningInput: false),
            .init(id: 2, pid: 101, bundleID: "com.openai.chat", runningOutput: false, runningInput: false)
        ])
        #expect(AudioActivityMonitor.activeDeferListBundleIDs(probe: probe).isEmpty)
    }

    @Test func activeDeferList_picksUpZoomOutput() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "us.zoom.xos", runningOutput: true, runningInput: false)
        ])
        let active = AudioActivityMonitor.activeDeferListBundleIDs(probe: probe)
        #expect(active == ["us.zoom.xos"])
    }

    @Test func activeDeferList_ignoresProcessesNotInDeferList() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "com.spotify.client", runningOutput: true, runningInput: false),
            .init(id: 2, pid: 101, bundleID: "com.apple.Music", runningOutput: true, runningInput: false)
        ])
        #expect(AudioActivityMonitor.activeDeferListBundleIDs(probe: probe).isEmpty)
    }

    @Test func activeDeferList_returnsMultipleWhenMultipleActive() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "us.zoom.xos", runningOutput: true, runningInput: false),
            .init(id: 2, pid: 101, bundleID: "com.anthropic.claudefordesktop", runningOutput: true, runningInput: false),
            .init(id: 3, pid: 102, bundleID: "com.spotify.client", runningOutput: true, runningInput: false)
        ])
        let active = Set(AudioActivityMonitor.activeDeferListBundleIDs(probe: probe))
        #expect(active == ["us.zoom.xos", "com.anthropic.claudefordesktop"])
    }

    @Test func activeDeferList_respectsCustomDeferList() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "us.zoom.xos", runningOutput: true, runningInput: false),
            .init(id: 2, pid: 101, bundleID: "com.example.custom", runningOutput: true, runningInput: false)
        ])
        let active = AudioActivityMonitor.activeDeferListBundleIDs(
            deferList: ["com.example.custom"],
            probe: probe
        )
        #expect(active == ["com.example.custom"])
    }

    @Test func activeDeferList_skipsProcessesWithoutBundleID() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: nil, runningOutput: true, runningInput: false),
            .init(id: 2, pid: 101, bundleID: "us.zoom.xos", runningOutput: true, runningInput: false)
        ])
        let active = AudioActivityMonitor.activeDeferListBundleIDs(probe: probe)
        #expect(active == ["us.zoom.xos"])
    }

    // MARK: - isAnyProcessUsingMicrophone

    @Test func mic_falseWhenNoProcessesUsingInput() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "com.example.foo", runningOutput: false, runningInput: false)
        ])
        #expect(!AudioActivityMonitor.isAnyProcessUsingMicrophone(probe: probe, ownPID: 999, ownBundleID: "com.malpern.voxclaw"))
    }

    @Test func mic_trueWhenAnyProcessUsesInput() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "com.aquavoice", runningOutput: false, runningInput: true)
        ])
        #expect(AudioActivityMonitor.isAnyProcessUsingMicrophone(probe: probe, ownPID: 999, ownBundleID: "com.malpern.voxclaw"))
    }

    @Test func mic_excludesOwnPID() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 999, bundleID: "com.something.else", runningOutput: false, runningInput: true)
        ])
        // Even though this fake process is using mic, it's our PID — should be ignored.
        #expect(!AudioActivityMonitor.isAnyProcessUsingMicrophone(probe: probe, ownPID: 999, ownBundleID: "com.malpern.voxclaw"))
    }

    @Test func mic_excludesOwnBundleID() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "com.malpern.voxclaw", runningOutput: false, runningInput: true)
        ])
        #expect(!AudioActivityMonitor.isAnyProcessUsingMicrophone(probe: probe, ownPID: 999, ownBundleID: "com.malpern.voxclaw"))
    }

    @Test func mic_doesNotConfuseInputWithOutput() {
        let probe = FakeCoreAudioProbe(processes: [
            // Process is producing OUTPUT but not capturing INPUT — mic check should ignore.
            .init(id: 1, pid: 100, bundleID: "com.spotify.client", runningOutput: true, runningInput: false)
        ])
        #expect(!AudioActivityMonitor.isAnyProcessUsingMicrophone(probe: probe, ownPID: 999, ownBundleID: "com.malpern.voxclaw"))
    }

    @Test func mic_returnsTrueIfAnyOfManyIsUsingInput() {
        let probe = FakeCoreAudioProbe(processes: [
            .init(id: 1, pid: 100, bundleID: "com.spotify.client", runningOutput: true, runningInput: false),
            .init(id: 2, pid: 101, bundleID: "com.zoom.us", runningOutput: false, runningInput: false),
            .init(id: 3, pid: 102, bundleID: "com.aquavoice", runningOutput: false, runningInput: true),
            .init(id: 4, pid: 103, bundleID: "com.example", runningOutput: false, runningInput: false)
        ])
        #expect(AudioActivityMonitor.isAnyProcessUsingMicrophone(probe: probe, ownPID: 999, ownBundleID: "com.malpern.voxclaw"))
    }
}
#endif
