#if os(macOS)
import AppKit
import os
import SwiftUI

public struct VoxClawLauncher {
    @MainActor public static func main() {
        let args = ProcessInfo.processInfo.arguments
        let currentPID = ProcessInfo.processInfo.processIdentifier
        Log.app.info("launch args: \(args, privacy: .public)")
        Log.app.info("bundlePath: \(Bundle.main.bundlePath, privacy: .public)")
        Log.app.debug("isatty: \(isatty(STDIN_FILENO), privacy: .public)")

        let mode = ModeDetector.detect()
        Log.app.info("mode: \(String(describing: mode), privacy: .public)")

        switch mode {
        case .cli:
            Log.app.info("entering CLI mode")
            CLIParser.main()
        case .menuBar:
            let terminated = terminateOtherMenuBarInstances(currentPID: currentPID)
            SharedApp.appState.autoClosedInstancesOnLaunch = terminated
            Log.app.info("entering menuBar mode")
            VoxClawApp.main()
        }
    }

    @MainActor
    private static func terminateOtherMenuBarInstances(currentPID: Int32) -> Int {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.malpern.voxclaw"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        var terminatedCount = 0

        for app in running where app.processIdentifier != currentPID {
            let terminated = app.terminate() || app.forceTerminate()
            if terminated {
                Log.app.warning("Terminated older VoxClaw instance pid=\(app.processIdentifier, privacy: .public)")
                terminatedCount += 1
            } else {
                Log.app.error("Failed to terminate older VoxClaw instance pid=\(app.processIdentifier, privacy: .public)")
            }
        }
        return terminatedCount
    }
}

/// Shared references for App Intents (which run in-process but can't access @State).
@MainActor
enum SharedApp {
    static let appState = AppState()
    static let coordinator = AppCoordinator()
    static let settings = SettingsManager()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?
    private var splashWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var authFailureObserver: NSObjectProtocol?
    private var keyMissingObserver: NSObjectProtocol?
    private var elevenLabsAuthFailureObserver: NSObjectProtocol?
    private var hasShownOpenAIAuthAlert = false
    private var hasShownOpenAIKeyMissingAlert = false
    private var hasShownElevenLabsAuthAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        authFailureObserver = NotificationCenter.default.addObserver(
            forName: .voxClawOpenAIAuthFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let message = note.userInfo?[VoxClawNotificationUserInfo.openAIAuthErrorMessage] as? String
            MainActor.assumeIsolated {
                self?.showOpenAIAuthAlert(errorMessage: message)
            }
        }

        keyMissingObserver = NotificationCenter.default.addObserver(
            forName: .voxClawOpenAIKeyMissing,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showOpenAIKeyMissingAlert()
            }
        }

        elevenLabsAuthFailureObserver = NotificationCenter.default.addObserver(
            forName: .voxClawElevenLabsAuthFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let message = note.userInfo?[VoxClawNotificationUserInfo.elevenLabsAuthErrorMessage] as? String
            MainActor.assumeIsolated {
                self?.showElevenLabsAuthAlert(errorMessage: message)
            }
        }

        BrowserControlService.shared.start()
        do {
            try BrowserExtensionInstaller().installBundledSupport()
        } catch {
            Log.playback.warning("Browser extension support install failed: \(error.localizedDescription, privacy: .public)")
            SharedApp.appState.browserControlWarning = "Browser extension support is not installed yet. Open Settings to install or refresh it."
        }

        if SharedApp.settings.networkListenerEnabled {
            SharedApp.coordinator.startListening(
                appState: SharedApp.appState,
                settings: SharedApp.settings,
                port: SharedApp.settings.networkListenerPort
            )
        }

        if SharedApp.settings.hasCompletedOnboarding {
            showSplash()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to VoxClaw"
        window.contentView = NSHostingView(rootView: OnboardingView(settings: SharedApp.settings))
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Log.onboarding.info("Onboarding window shown")
    }

    private func showSplash() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 260),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.contentView = NSHostingView(rootView:
            SplashView()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.orderFrontRegardless()
        splashWindow = window

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }

        // Dismiss after 1.5s
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.dismissSplash()
        }
        Log.app.info("Splash shown")
    }

    private func dismissSplash() {
        guard let window = splashWindow else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.splashWindow?.close()
                self?.splashWindow = nil
            }
        })
    }

    private func showOpenAIAuthAlert(errorMessage: String?) {
        guard !hasShownOpenAIAuthAlert else { return }
        hasShownOpenAIAuthAlert = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OpenAI key rejected (HTTP 401)"
        alert.informativeText = """
        OpenAI rejected your API key, so VoxClaw switched to Apple voice for this read.

        \(errorMessage ?? "Generate a new key in OpenAI, then paste it in VoxClaw Settings.")
        """
        alert.addButton(withTitle: "Get New Key")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://platform.openai.com/api-keys") {
                NSWorkspace.shared.open(url)
            }
            presentSettingsWindow()
        } else if response == .alertSecondButtonReturn {
            presentSettingsWindow()
        }
    }

    private func showOpenAIKeyMissingAlert() {
        guard !hasShownOpenAIKeyMissingAlert else { return }
        hasShownOpenAIKeyMissingAlert = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No OpenAI API key"
        alert.informativeText = """
        OpenAI is selected as your voice engine, but no API key is configured. \
        VoxClaw used Apple voice for this read.

        Add your OpenAI API key in Settings to use neural voices.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            presentSettingsWindow()
        }
    }

    private func showElevenLabsAuthAlert(errorMessage: String?) {
        guard !hasShownElevenLabsAuthAlert else { return }
        hasShownElevenLabsAuthAlert = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ElevenLabs key rejected (HTTP 401)"
        alert.informativeText = """
        ElevenLabs rejected your API key, so VoxClaw switched to Apple voice for this read.

        \(errorMessage ?? "Generate a new key at elevenlabs.io, then paste it in VoxClaw Settings.")
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            presentSettingsWindow()
        }
    }

    private func presentSettingsWindow() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 740),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoxClaw Settings"
        window.contentView = NSHostingView(rootView: SettingsView(settings: SharedApp.settings, appState: SharedApp.appState))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct VoxClawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private var appState: AppState { SharedApp.appState }
    private var coordinator: AppCoordinator { SharedApp.coordinator }
    private var settings: SettingsManager { SharedApp.settings }

    /// Retains the Services menu provider for the lifetime of the app.
    @State private var serviceProvider: VoxClawServiceProvider?

    init() {
        Log.app.info("App init, creating MenuBarExtra")
    }

    var body: some Scene {
        MenuBarExtra("VoxClaw", systemImage: "waveform") {
            MenuBarView(
                appState: appState,
                settings: settings,
                onTogglePause: { coordinator.togglePause() },
                onStop: { coordinator.stop() },
                onReadText: { text in await coordinator.readText(text, appState: appState, settings: settings) }
            )
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .task {
                setupServicesProvider()
                await coordinator.handleCLILaunch(appState: appState, settings: settings)
            }
            .onChange(of: settings.networkListenerEnabled) { _, enabled in
                if enabled {
                    coordinator.startListening(appState: appState, settings: settings, port: settings.networkListenerPort)
                } else {
                    coordinator.stopListening()
                }
            }
            .onChange(of: settings.networkListenerPort) { _, port in
                guard settings.networkListenerEnabled else { return }
                coordinator.stopListening()
                coordinator.startListening(appState: appState, settings: settings, port: port)
            }
            .onChange(of: settings.voiceSpeed) { _, newSpeed in
                coordinator.setSpeed(newSpeed)
            }
        }

        Window("VoxClaw Settings", id: "settings") {
            SettingsView(settings: settings, appState: appState)
        }
        .defaultSize(width: 440, height: 420)

        Window("About VoxClaw", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

    }

    // MARK: - URL Scheme (voxclaw://read?text=...)

    private func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "voxclaw" else { return }

        switch components.host {
        case "read":
            if let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
               !text.isEmpty {
                Log.app.info("Received text via URL scheme (\(text.count) chars)")
                Task {
                    await coordinator.readText(text, appState: appState, settings: settings)
                }
            }
        case "settings":
            Log.app.info("Opening settings via URL scheme")
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        default:
            Log.app.warning("Unknown URL action: \(components.host ?? "nil")")
        }
    }

    // MARK: - Services Menu

    private func setupServicesProvider() {
        let provider = VoxClawServiceProvider { text in
            await coordinator.readText(text, appState: appState, settings: settings)
        }
        NSApplication.shared.servicesProvider = provider
        serviceProvider = provider
        Log.app.info("Registered macOS Services provider")
    }
}

@Observable
@MainActor
final class AppCoordinator {
    private var networkListener: NetworkListener?
    private var activeSession: ReadingSession?
    let voiceAssigner = VoiceAssigner(store: VoiceBindingStore(fileURL: VoiceBindingStore.defaultURL()))

    private struct SpeechItem {
        let text: String
        let engineOverride: (any SpeechEngine)?
        let audioOnlyOverride: Bool?
        let projectId: String?
    }
    private var speechQueue: [SpeechItem] = []
    private var isDrainingQueue = false
    private var projectActivity = ProjectActivityTracker()
    private var currentDrainingProjectId: String?
    private static let maxQueueSize = 20
    private static let interItemDelay: Duration = .seconds(2)
    /// Maximum total time we'll politely wait for a defer-list app (Zoom, Claude
    /// desktop, etc.) to stop producing audio before falling back to silent display.
    private static let politeWaitMax: Duration = .seconds(150)
    /// How often we re-poll CoreAudio for defer-list activity while waiting.
    private static let politePollInterval: Duration = .seconds(1)

    func startListening(appState: AppState, settings: SettingsManager, port: UInt16? = nil) {
        stopListening()
        let port = port ?? CLIContext.shared?.port ?? 4140
        let listener = NetworkListener(port: port, appState: appState, settings: settings)
        do {
            let assigner = voiceAssigner
            try listener.start(
                onReadRequest: { [weak self] request in
                    await self?.handleReadRequest(request, appState: appState, settings: settings)
                },
                voiceBindingCountProvider: { @Sendable in await assigner.bindingCount() }
            )
            self.networkListener = listener
        } catch {
            Log.app.error("Failed to start listener: \(error)")
        }
    }

    private func handleReadRequest(_ request: ReadRequest, appState: AppState, settings: SettingsManager) async {
        let engine = await makeEngine(for: request, settings: settings)
        await readText(
            request.text,
            appState: appState,
            settings: settings,
            engineOverride: engine,
            projectId: request.projectId
        )
    }

    /// Constructs the speech engine for a /read request, factoring in the project/agent
    /// voice binding, available API keys, and per-request overrides. Returns nil when
    /// the caller should fall back to `settings.createEngine()`.
    private func makeEngine(for request: ReadRequest, settings: SettingsManager) async -> (any SpeechEngine)? {
        let rate = request.rate ?? settings.voiceSpeed
        let instructions = request.instructions ?? (settings.readingStyle.isEmpty ? nil : settings.readingStyle)

        let assignedOpenAI = await voiceAssigner.resolveVoice(
            projectId: request.projectId,
            agentId: request.agentId,
            engine: .openai
        )
        let openaiVoice = request.voice ?? assignedOpenAI ?? settings.openAIVoice

        let assignedApple = await voiceAssigner.resolveVoice(
            projectId: request.projectId,
            agentId: request.agentId,
            engine: .apple
        )
        let appleVoice = assignedApple ?? settings.appleVoiceIdentifier

        if !settings.openAIAPIKey.isEmpty {
            let primary = OpenAISpeechEngine(apiKey: settings.openAIAPIKey, voice: openaiVoice, speed: rate, instructions: instructions)
            let fallback = AppleSpeechEngine(voiceIdentifier: appleVoice, rate: rate)
            return FallbackSpeechEngine(primary: primary, fallback: fallback)
        }
        if request.projectId != nil {
            return AppleSpeechEngine(voiceIdentifier: appleVoice, rate: rate)
        }
        if request.rate != nil {
            return AppleSpeechEngine(rate: rate)
        }
        return nil
    }

    func stopListening() {
        networkListener?.stop()
        networkListener = nil
    }

    func readText(
        _ text: String,
        appState: AppState,
        settings: SettingsManager,
        audioOnlyOverride: Bool? = nil,
        engineOverride: (any SpeechEngine)? = nil,
        projectId: String? = nil
    ) async {
        let item = SpeechItem(
            text: text,
            engineOverride: engineOverride,
            audioOnlyOverride: audioOnlyOverride,
            projectId: projectId
        )
        enqueueSpeech(item, appState: appState, settings: settings)
    }

    private func enqueueSpeech(_ item: SpeechItem, appState: AppState, settings: SettingsManager) {
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

        while !speechQueue.isEmpty {
            let item = speechQueue.removeFirst()

            currentDrainingProjectId = item.projectId
            rebuildProjectIndicators(appState: appState)

            // Politely wait if any "blocker" is active: a defer-list app
            // (Zoom, Claude desktop, etc.) producing audio, OR any non-VoxClaw
            // process using the microphone (Aqua Voice, Superwhisper, etc.).
            // Falls back to silent display after the polite-wait window expires.
            let goSilent = await waitForBlockersIfNeeded(item: item)

            appState.audioOnly = item.audioOnlyOverride ?? settings.audioOnly
            let engine: any SpeechEngine
            if goSilent {
                appState.audioOnly = false  // silent mode still shows the panel
                appState.silentMode = true
                engine = SilentSpeechEngine(rate: settings.voiceSpeed)
                Log.session.info("Queue item going silent: defer-list still active after polite wait")
            } else {
                appState.silentMode = false
                engine = item.engineOverride ?? settings.createEngine()
            }

            let session = ReadingSession(
                appState: appState,
                engine: engine,
                settings: settings,
                pauseExternalAudioDuringSpeech: !goSilent && settings.pauseOtherAudioDuringSpeech
            )
            session.onUserStop = { [weak self] in self?.stop() }
            session.keepPanelOnFinish = !speechQueue.isEmpty
            activeSession = session
            Log.session.info("Queue draining item: chars=\(item.text.count, privacy: .public), remaining=\(self.speechQueue.count, privacy: .public), silent=\(goSilent, privacy: .public)")
            await session.start(text: item.text)

            // Monitor for mid-speech blockers (mic, defer-list apps becoming
            // active while we're already speaking). Only meaningful for audio
            // playback — silent mode is already non-disruptive.
            #if os(macOS)
            let monitorTask = goSilent ? nil : Task { @MainActor [weak self, weak session] in
                await self?.monitorBlockersDuringSpeech(session: session)
            }
            #endif

            await session.waitUntilFinished()
            #if os(macOS)
            monitorTask?.cancel()
            #endif
            appState.silentMode = false

            // Animate project indicators: remove current, slide upcoming left.
            currentDrainingProjectId = nil
            rebuildProjectIndicators(appState: appState)

            if !speechQueue.isEmpty {
                try? await Task.sleep(for: Self.interItemDelay)
                // Swap panels: close the old one instantly, new session will
                // create a fresh panel at the same position.
                session.dismissPanel()
            }
            activeSession = nil
        }
    }

    /// Polls CoreAudio for "blocker" activity: defer-list apps producing audio
    /// (Zoom, Claude desktop, etc.) or any process using the microphone (Aqua
    /// Voice, Superwhisper, etc.). Returns false if the path is clear (or the
    /// platform doesn't support detection); returns true if we waited the full
    /// polite-wait window and should fall back to silent display.
    private func waitForBlockersIfNeeded(item: SpeechItem) async -> Bool {
        #if os(macOS)
        var blockers = currentBlockers()
        if blockers.isEmpty { return false }

        Log.session.info("Polite wait: blockers=\(blockers.joined(separator: ","), privacy: .public)")
        let deadline = ContinuousClock.now.advanced(by: Self.politeWaitMax)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.politePollInterval)
            blockers = currentBlockers()
            if blockers.isEmpty {
                Log.session.info("Polite wait: blockers cleared, will speak after inter-item gap")
                try? await Task.sleep(for: Self.interItemDelay)
                return false
            }
        }
        Log.session.info("Polite wait: timed out after \(Int(Self.politeWaitMax.components.seconds), privacy: .public)s, falling back to silent. Blockers still active=\(blockers.joined(separator: ","), privacy: .public)")
        return true
        #else
        return false
        #endif
    }

    #if os(macOS)
    /// Aggregates currently-active reasons we should not speak aloud.
    /// Returns bundle IDs for audio-producing defer-list apps, plus the
    /// sentinel "mic" if any non-VoxClaw process is using the microphone.
    private func currentBlockers() -> [String] {
        var blockers = AudioActivityMonitor.activeDeferListBundleIDs()
        if AudioActivityMonitor.isAnyProcessUsingMicrophone() {
            blockers.append("mic")
        }
        return blockers
    }

    /// Polls for blockers while a session is actively playing audio. When a
    /// blocker becomes active, pauses the engine and waits up to the polite-wait
    /// window for it to clear; on clear, resumes after the inter-item gap; on
    /// timeout, stops the current session (the next queue item will re-decide
    /// audio vs silent on its own polite-wait pass).
    private func monitorBlockersDuringSpeech(session: ReadingSession?) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.politePollInterval)
            if Task.isCancelled { return }
            guard let session, !session.hasFinished else { return }

            let blockers = currentBlockers()
            guard !blockers.isEmpty else { continue }

            Log.session.info("Mid-speech blockers detected: \(blockers.joined(separator: ","), privacy: .public) — pausing")
            session.pauseForBlocker()

            let deadline = ContinuousClock.now.advanced(by: Self.politeWaitMax)
            var cleared = false
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: Self.politePollInterval)
                if Task.isCancelled { return }
                if currentBlockers().isEmpty {
                    cleared = true
                    break
                }
            }

            if cleared {
                Log.session.info("Mid-speech blockers cleared, resuming after inter-item gap")
                try? await Task.sleep(for: Self.interItemDelay)
                if Task.isCancelled { return }
                session.resumeFromBlocker()
            } else {
                Log.session.info("Mid-speech polite wait timed out, stopping current item")
                session.stop()
                return
            }
        }
    }
    #endif

    /// Rebuilds `appState.projectIndicators` from the currently-draining
    /// project + distinct upcoming projects in the speech queue. Produces an
    /// empty list when <2 projects are in the activity window so single-
    /// project use stays uncluttered.
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

    func togglePause() {
        activeSession?.togglePause()
    }

    func stop() {
        let cleared = speechQueue.count
        speechQueue.removeAll()
        if cleared > 0 {
            Log.session.info("Stop: cleared \(cleared, privacy: .public) queued speech items")
        }
        activeSession?.stop()
        activeSession = nil
    }

    func setSpeed(_ speed: Float) {
        activeSession?.setSpeed(speed)
    }

    func handleCLILaunch(appState: AppState, settings: SettingsManager) async {
        guard let context = CLIContext.shared else { return }

        // Small delay to let the app finish initializing
        try? await Task.sleep(for: .milliseconds(100))

        if context.listen {
            startListening(appState: appState, settings: settings, port: context.port)
        } else if let text = context.text {
            let instructions = context.instructions ?? (settings.readingStyle.isEmpty ? nil : settings.readingStyle)
            let engine: any SpeechEngine
            if let apiKey = try? KeychainHelper.readAPIKey() {
                engine = OpenAISpeechEngine(apiKey: apiKey, voice: context.voice, speed: context.rate, instructions: instructions)
            } else {
                engine = AppleSpeechEngine(rate: context.rate)
            }
            await readText(text, appState: appState, settings: settings,
                           audioOnlyOverride: context.audioOnly, engineOverride: engine)
        }
    }
}
#endif
