import Foundation
import SwiftUI
import os

/// Platform-specific behaviors injected by the owning coordinator.
@MainActor
public protocol SpeechQueueDelegate: AnyObject {
    func makeEngine(for item: SpeechQueueCoordinator.QueueItem, settings: SettingsManager) async -> (any SpeechEngine)?
    func currentBlockers() -> [String]
    func onControlAction(_ action: HTTPRequestParser.ControlAction)
    func onAckReceived(projectId: String)
}

/// Default implementations so iOS doesn't need to implement blocker/relay stubs.
public extension SpeechQueueDelegate {
    func currentBlockers() -> [String] { [] }
    func onControlAction(_ action: HTTPRequestParser.ControlAction) {}
    func onAckReceived(projectId: String) {}
}

/// Platform-independent speech queue with project badges, transitions,
/// polite-wait, ack handling, and session timeout. Used by both macOS
/// AppCoordinator and iOS iOSCoordinator.
@Observable
@MainActor
public final class SpeechQueueCoordinator {
    public struct QueueItem {
        public let text: String
        public let engineOverride: (any SpeechEngine)?
        public let audioOnlyOverride: Bool?
        public let projectId: String?

        public init(text: String, engineOverride: (any SpeechEngine)? = nil, audioOnlyOverride: Bool? = nil, projectId: String? = nil) {
            self.text = text
            self.engineOverride = engineOverride
            self.audioOnlyOverride = audioOnlyOverride
            self.projectId = projectId
        }
    }

    public weak var delegate: SpeechQueueDelegate?
    public private(set) var activeSession: ReadingSession?

    private var speechQueue: [QueueItem] = []
    private var isDrainingQueue = false
    private var projectActivity = ProjectActivityTracker()
    private(set) var currentDrainingProjectId: String?
    private var isCurrentItemAcked = false

    private static let maxQueueSize = 20
    private static let interItemDelay: Duration = .seconds(1)
    static let politeWaitMax: Duration = .seconds(150)
    static let politePollInterval: Duration = .seconds(1)

    public init() {}

    // MARK: - Public API

    public func enqueue(
        _ text: String,
        appState: AppState,
        settings: SettingsManager,
        audioOnlyOverride: Bool? = nil,
        engineOverride: (any SpeechEngine)? = nil,
        projectId: String? = nil
    ) {
        let item = QueueItem(
            text: text,
            engineOverride: engineOverride,
            audioOnlyOverride: audioOnlyOverride,
            projectId: projectId
        )
        enqueueItem(item, appState: appState, settings: settings)
    }

    public func togglePause() {
        activeSession?.togglePause()
        delegate?.onControlAction(activeSession != nil && !(activeSession?.hasFinished ?? true) ? .pause : .resume)
    }

    public func stop() {
        let cleared = speechQueue.count
        speechQueue.removeAll()
        if cleared > 0 {
            Log.session.info("Stop: cleared \(cleared, privacy: .public) queued speech items")
        }
        activeSession?.stop()
        activeSession = nil
        delegate?.onControlAction(.stop)
    }

    public func setSpeed(_ speed: Float) {
        activeSession?.setSpeed(speed)
    }

    public func handleAck(projectId: String, appState: AppState) {
        Log.session.info("Ack received for project: \(projectId, privacy: .public)")

        if currentDrainingProjectId == projectId {
            Log.session.info("Ack: marking current session as acknowledged")
            isCurrentItemAcked = true
            #if os(macOS)
            NSSound(named: "Submarine")?.play()
            #endif
        }

        let before = speechQueue.count
        speechQueue.removeAll { $0.projectId == projectId }
        let removed = before - speechQueue.count
        if removed > 0 {
            Log.session.info("Ack: removed \(removed, privacy: .public) queued items for project")
            rebuildProjectIndicators(appState: appState)
        }

        delegate?.onAckReceived(projectId: projectId)
    }

    public func handleControl(_ control: HTTPRequestParser.ControlRequest, deviceID: String) {
        if control.origin == deviceID { return }
        Log.session.info("Control: \(control.action.rawValue, privacy: .public)")
        switch control.action {
        case .pause:
            if !(activeSession?.hasFinished ?? true) {
                activeSession?.togglePause()
            }
        case .resume:
            if !(activeSession?.hasFinished ?? true) {
                activeSession?.togglePause()
            }
        case .stop:
            stop()
        }
    }

    // MARK: - Queue internals

    private func enqueueItem(_ item: QueueItem, appState: AppState, settings: SettingsManager) {
        if speechQueue.count >= Self.maxQueueSize {
            Log.session.warning("Speech queue at cap (\(Self.maxQueueSize, privacy: .public)), dropping oldest")
            speechQueue.removeFirst()
        }
        speechQueue.append(item)
        Log.session.info("Enqueued speech: chars=\(item.text.count, privacy: .public), depth=\(self.speechQueue.count, privacy: .public)")
        if let pid = item.projectId, !pid.isEmpty {
            projectActivity.record(pid)
        }
        rebuildProjectIndicators(appState: appState)
        if !isDrainingQueue {
            Task { @MainActor in
                await self.drainQueue(appState: appState, settings: settings)
            }
        }
    }

    private func drainQueue(appState: AppState, settings: SettingsManager) async {
        guard !isDrainingQueue else { return }
        isDrainingQueue = true
        defer { isDrainingQueue = false }

        #if os(macOS)
        var sharedPanel: PanelController?
        #endif

        while !speechQueue.isEmpty {
            let item = speechQueue.removeFirst()
            let hasMoreItems = !speechQueue.isEmpty

            currentDrainingProjectId = item.projectId
            rebuildProjectIndicators(appState: appState)

            let goSilent = await waitForBlockersIfNeeded()

            appState.audioOnly = item.audioOnlyOverride ?? settings.audioOnly
            let engine: any SpeechEngine
            if goSilent {
                appState.audioOnly = false
                appState.silentMode = true
                engine = SilentSpeechEngine(rate: settings.voiceSpeed)
                Log.session.info("Queue item going silent: defer-list still active after polite wait")
            } else {
                appState.silentMode = false
                engine = await delegate?.makeEngine(for: item, settings: settings)
                    ?? item.engineOverride
                    ?? settings.createEngine()
            }

            #if os(macOS)
            if !appState.audioOnly && sharedPanel == nil {
                sharedPanel = PanelController(appState: appState, settings: settings, onTogglePause: { [weak self] in
                    self?.togglePause()
                }, onStop: { [weak self] in
                    self?.stop()
                })
            }
            #endif

            #if os(macOS)
            let session = ReadingSession(
                appState: appState,
                engine: engine,
                settings: settings,
                pauseExternalAudioDuringSpeech: !goSilent && settings.pauseOtherAudioDuringSpeech,
                externalPanelController: sharedPanel
            )
            #else
            let session = ReadingSession(
                appState: appState,
                engine: engine,
                settings: settings,
                pauseExternalAudioDuringSpeech: !goSilent && settings.pauseOtherAudioDuringSpeech
            )
            #endif
            session.onUserStop = { [weak self] in self?.stop() }
            session.keepPanelOnFinish = hasMoreItems
            activeSession = session
            isCurrentItemAcked = false
            Log.session.info("Queue draining item: chars=\(item.text.count, privacy: .public), remaining=\(self.speechQueue.count, privacy: .public), silent=\(goSilent, privacy: .public)")
            await session.start(text: item.text)

            #if os(macOS)
            let monitorTask = goSilent ? nil : Task { @MainActor [weak self, weak session] in
                await self?.monitorBlockersDuringSpeech(session: session)
            }
            #endif

            let ackTask = Task { @MainActor [weak self, weak session] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, let session, !session.hasFinished else { return }
                    if self.isCurrentItemAcked {
                        Log.session.info("Ack detected mid-speech, stopping current item")
                        session.stop()
                        return
                    }
                }
            }

            await session.waitUntilFinished()
            ackTask.cancel()
            #if os(macOS)
            monitorTask?.cancel()
            #endif
            isCurrentItemAcked = false
            appState.silentMode = false

            currentDrainingProjectId = nil
            rebuildProjectIndicators(appState: appState)

            if hasMoreItems {
                try? await Task.sleep(for: Self.interItemDelay)
            }
            activeSession = nil
        }

        #if os(macOS)
        sharedPanel?.dismiss()
        sharedPanel = nil
        #endif
        appState.reset()
    }

    // MARK: - Blockers

    private func waitForBlockersIfNeeded() async -> Bool {
        guard let delegate else { return false }
        var blockers = delegate.currentBlockers()
        if blockers.isEmpty { return false }

        Log.session.info("Polite wait: blockers=\(blockers.joined(separator: ","), privacy: .public)")
        let deadline = ContinuousClock.now.advanced(by: Self.politeWaitMax)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.politePollInterval)
            blockers = delegate.currentBlockers()
            if blockers.isEmpty {
                Log.session.info("Polite wait: blockers cleared, will speak after inter-item gap")
                try? await Task.sleep(for: Self.interItemDelay)
                return false
            }
        }
        Log.session.info("Polite wait: timed out, falling back to silent")
        return true
    }

    #if os(macOS)
    private func monitorBlockersDuringSpeech(session: ReadingSession?) async {
        var consecutiveBlockerPolls = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.politePollInterval)
            if Task.isCancelled { return }
            guard let session, !session.hasFinished else { return }

            let blockers = delegate?.currentBlockers() ?? []
            if blockers.isEmpty {
                consecutiveBlockerPolls = 0
                continue
            }
            consecutiveBlockerPolls += 1
            guard consecutiveBlockerPolls >= 2 else { continue }

            Log.session.info("Mid-speech blockers detected (sustained): \(blockers.joined(separator: ","), privacy: .public) — pausing")
            session.pauseForBlocker()
            delegate?.onControlAction(.pause)

            let deadline = ContinuousClock.now.advanced(by: Self.politeWaitMax)
            var cleared = false
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: Self.politePollInterval)
                if Task.isCancelled { return }
                if delegate?.currentBlockers().isEmpty ?? true {
                    cleared = true
                    break
                }
            }

            if cleared {
                Log.session.info("Mid-speech blockers cleared, resuming after inter-item gap")
                try? await Task.sleep(for: Self.interItemDelay)
                if Task.isCancelled { return }
                session.resumeFromBlocker()
                delegate?.onControlAction(.resume)
            } else {
                Log.session.info("Mid-speech polite wait timed out, stopping current item")
                session.stop()
                return
            }
        }
    }
    #endif

    // MARK: - Project indicators

    private func rebuildProjectIndicators(appState: AppState) {
        guard projectActivity.distinctProjectsInWindow() >= 2 else {
            appState.projectIndicators = []
            return
        }
        var seen = Set<String>()
        var indicators: [ProjectIndicator] = []
        if let pid = currentDrainingProjectId, !pid.isEmpty, seen.insert(pid).inserted {
            indicators.append(ProjectIndicator(projectId: pid))
        }
        for item in speechQueue {
            if let pid = item.projectId, !pid.isEmpty, seen.insert(pid).inserted {
                indicators.append(ProjectIndicator(projectId: pid))
            }
        }
        appState.projectIndicators = indicators
    }
}
