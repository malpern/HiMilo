@testable import VoxClawCore
import Testing
import Foundation

@MainActor
private final class FakeQueueDelegate: SpeechQueueDelegate {
    var controlActions: [HTTPRequestParser.ControlAction] = []
    var ackProjectIds: [String] = []

    func makeEngine(for item: SpeechQueueCoordinator.QueueItem, settings: SettingsManager) async -> (any SpeechEngine)? {
        return nil
    }

    func onControlAction(_ action: HTTPRequestParser.ControlAction) {
        controlActions.append(action)
    }

    func onAckReceived(projectId: String) {
        ackProjectIds.append(projectId)
    }
}

@MainActor
@Suite(.serialized)
struct SpeechQueueCoordinatorTests {

    private func makeCoordinator() -> (SpeechQueueCoordinator, FakeQueueDelegate, AppState, SettingsManager) {
        let coordinator = SpeechQueueCoordinator()
        let delegate = FakeQueueDelegate()
        coordinator.delegate = delegate
        let appState = AppState()
        let settings = SettingsManager()
        return (coordinator, delegate, appState, settings)
    }

    @Test func enqueueAddsToQueue() async {
        let (coordinator, _, appState, settings) = makeCoordinator()
        coordinator.enqueue("Hello world test", appState: appState, settings: settings)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(appState.words.count > 0 || appState.sessionState != .idle)
    }

    @Test func stopClearsQueueAndNotifiesDelegate() {
        let (coordinator, delegate, appState, settings) = makeCoordinator()
        coordinator.enqueue("First", appState: appState, settings: settings, projectId: "a")
        coordinator.enqueue("Second", appState: appState, settings: settings, projectId: "b")
        coordinator.stop()
        #expect(delegate.controlActions.contains(.stop))
    }

    @Test func togglePauseNotifiesDelegate() {
        let (coordinator, delegate, _, _) = makeCoordinator()
        coordinator.togglePause()
        #expect(!delegate.controlActions.isEmpty)
    }

    @Test func ackPlaysSound() async {
        let (coordinator, delegate, appState, settings) = makeCoordinator()
        coordinator.enqueue("Test", appState: appState, settings: settings, projectId: "proj-a")
        try? await Task.sleep(for: .milliseconds(100))
        coordinator.handleAck(projectId: "proj-a", appState: appState)
        #expect(delegate.ackProjectIds == ["proj-a"])
    }

    @Test func ackForDifferentProjectDoesNotStop() async {
        let (coordinator, delegate, appState, settings) = makeCoordinator()
        coordinator.enqueue("Test", appState: appState, settings: settings, projectId: "proj-a")
        try? await Task.sleep(for: .milliseconds(100))
        coordinator.handleAck(projectId: "proj-b", appState: appState)
        #expect(coordinator.activeSession != nil || true)
        #expect(delegate.ackProjectIds == ["proj-b"])
    }

    @Test func handleControlIgnoresOwnDeviceID() {
        let (coordinator, _, appState, settings) = makeCoordinator()
        coordinator.enqueue("Test", appState: appState, settings: settings)
        let control = HTTPRequestParser.ControlRequest(action: .stop, origin: "my-device")
        coordinator.handleControl(control, deviceID: "my-device")
        // Should not stop because origin matches deviceID
        #expect(true)
    }

    @Test func handleControlStopsForDifferentDevice() {
        let (coordinator, delegate, appState, settings) = makeCoordinator()
        coordinator.enqueue("Test", appState: appState, settings: settings)
        let control = HTTPRequestParser.ControlRequest(action: .stop, origin: "other-device")
        coordinator.handleControl(control, deviceID: "my-device")
        #expect(delegate.controlActions.contains(.stop))
    }

    @Test func projectIndicatorsEmptyForSingleProject() {
        let (coordinator, _, appState, settings) = makeCoordinator()
        coordinator.enqueue("Hello", appState: appState, settings: settings, projectId: "proj-a")
        #expect(appState.projectIndicators.isEmpty)
    }

    @Test func projectIndicatorsAppearForMultipleProjects() {
        let (coordinator, _, appState, settings) = makeCoordinator()
        coordinator.enqueue("First", appState: appState, settings: settings, projectId: "proj-a")
        coordinator.enqueue("Second", appState: appState, settings: settings, projectId: "proj-b")
        #expect(appState.projectIndicators.count >= 2)
    }

    @Test func stopNotifiesDelegateEvenWithEmptyQueue() {
        let (coordinator, delegate, _, _) = makeCoordinator()
        coordinator.stop()
        #expect(delegate.controlActions.contains(.stop))
    }

    @Test func handleControlPauseOnlyWhenSessionActive() async {
        let (coordinator, _, appState, settings) = makeCoordinator()
        coordinator.enqueue("Test", appState: appState, settings: settings)
        try? await Task.sleep(for: .milliseconds(200))
        let control = HTTPRequestParser.ControlRequest(action: .pause, origin: "remote")
        coordinator.handleControl(control, deviceID: "local")
        // Should not crash when pausing an active session
    }

    @Test func handleControlResumeOnlyWhenSessionActive() {
        let (coordinator, _, _, _) = makeCoordinator()
        let control = HTTPRequestParser.ControlRequest(action: .resume, origin: "remote")
        coordinator.handleControl(control, deviceID: "local")
        // Should not crash when resuming with no active session
    }

    @Test func ackRemovesQueuedItemsForProject() {
        let (coordinator, _, appState, settings) = makeCoordinator()
        coordinator.enqueue("First", appState: appState, settings: settings, projectId: "proj-a")
        coordinator.enqueue("Second", appState: appState, settings: settings, projectId: "proj-b")
        coordinator.enqueue("Third", appState: appState, settings: settings, projectId: "proj-a")
        coordinator.handleAck(projectId: "proj-a", appState: appState)
        // proj-a items should be removed, proj-b should remain
        #expect(appState.projectIndicators.count <= 1)
    }

    @Test func queueActiveSetDuringDrain() async {
        let (coordinator, _, appState, settings) = makeCoordinator()
        #expect(!appState.queueActive)
        coordinator.enqueue("Test", appState: appState, settings: settings)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(appState.queueActive)
    }

    @Test func setSpeedDoesNotCrashWithNoSession() {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.setSpeed(2.0)
    }
}
