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
        window.contentView = NSHostingView(rootView: SettingsView(settings: SharedApp.settings, appState: SharedApp.appState, peerBrowser: SharedApp.coordinator.peerBrowser))
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
            SettingsView(settings: settings, appState: appState, peerBrowser: coordinator.peerBrowser)
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
final class AppCoordinator: SpeechQueueDelegate {
    private var networkListener: NetworkListener?
    let queue = SpeechQueueCoordinator()
    let voiceAssigner = VoiceAssigner(store: VoiceBindingStore(fileURL: VoiceBindingStore.defaultURL()))
    let peerBrowser = PeerBrowser()
    let deviceID = UUID().uuidString
    private var settingsRef: SettingsManager?

    func startListening(appState: AppState, settings: SettingsManager, port: UInt16? = nil) {
        stopListening()
        settingsRef = settings
        queue.delegate = self
        peerBrowser.start()
        let port = port ?? CLIContext.shared?.port ?? 4140
        let listener = NetworkListener(port: port, appState: appState, settings: settings)
        do {
            let assigner = voiceAssigner
            try listener.start(
                onReadRequest: { [weak self] request in
                    await self?.handleReadRequest(request, appState: appState, settings: settings)
                },
                onAck: { [weak self] projectId in
                    await self?.handleAck(projectId: projectId, appState: appState)
                },
                onControl: { [weak self] control in
                    await self?.handleControl(control)
                },
                voiceBindingCountProvider: { @Sendable in await assigner.bindingCount() }
            )
            self.networkListener = listener
        } catch {
            Log.app.error("Failed to start listener: \(error)")
        }
    }

    private func handleReadRequest(_ request: ReadRequest, appState: AppState, settings: SettingsManager) async {
        let assignedVoice = await voiceAssigner.resolveVoice(
            projectId: request.projectId,
            agentId: request.agentId,
            engine: .openai
        )
        let resolvedVoice = request.voice ?? assignedVoice ?? settings.openAIVoice

        var resolvedRequest = request
        resolvedRequest.voice = resolvedVoice

        let localMuted = settings.activeSpeakers.contains("__mute_local__") && !resolvedRequest.forceLocal
        if !localMuted {
            await readText(
                resolvedRequest.text,
                appState: appState,
                settings: settings,
                projectId: resolvedRequest.projectId
            )
        } else {
            Log.session.info("Local playback muted, skipping")
        }

        if !request.relayed {
            relayToPeers(request: resolvedRequest, settings: settings)
        }
    }

    private func relayToPeers(request: ReadRequest, settings: SettingsManager) {
        let relayIDs = settings.activeSpeakers
        guard !relayIDs.isEmpty else { return }

        for peer in peerBrowser.peers {
            guard relayIDs.contains(peer.id), let baseURL = peer.baseURL else { continue }
            guard let url = URL(string: "\(baseURL)/read") else { continue }

            Log.network.info("Relaying to peer \(peer.name, privacy: .public)")
            var payload: [String: Any] = ["text": request.text, "relayed": true]
            if let v = request.voice { payload["voice"] = v }
            if let r = request.rate { payload["rate"] = r }
            if let i = request.instructions { payload["instructions"] = i }
            if let p = request.projectId { payload["project_id"] = p }
            if let a = request.agentId { payload["agent_id"] = a }

            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
            urlRequest.timeoutInterval = 3

            let peerName = peer.name
            let req = urlRequest
            Task.detached {
                do {
                    let (_, response) = try await URLSession.shared.data(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    Log.network.info("Relay to \(peerName, privacy: .public): status=\(status, privacy: .public)")
                } catch {
                    Log.network.warning("Relay to \(peerName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func stopListening() {
        networkListener?.stop()
        networkListener = nil
    }

    // MARK: - SpeechQueueDelegate

    func makeEngine(for item: SpeechQueueCoordinator.QueueItem, settings: SettingsManager) async -> (any SpeechEngine)? {
        let rate = item.engineOverride != nil ? nil : settings.voiceSpeed
        guard item.engineOverride == nil else { return item.engineOverride }

        let request = ReadRequest(
            text: item.text,
            rate: rate,
            projectId: item.projectId
        )
        let assignedOpenAI = await voiceAssigner.resolveVoice(
            projectId: item.projectId,
            agentId: nil,
            engine: .openai
        )
        let openaiVoice = assignedOpenAI ?? settings.openAIVoice

        let assignedApple = await voiceAssigner.resolveVoice(
            projectId: item.projectId,
            agentId: nil,
            engine: .apple
        )
        let appleVoice = assignedApple ?? settings.appleVoiceIdentifier
        let engineRate = settings.voiceSpeed
        let instructions = settings.readingStyle.isEmpty ? nil : settings.readingStyle

        if !settings.openAIAPIKey.isEmpty {
            let primary = OpenAISpeechEngine(apiKey: settings.openAIAPIKey, voice: openaiVoice, speed: engineRate, instructions: instructions)
            let fallback = AppleSpeechEngine(voiceIdentifier: appleVoice, rate: engineRate)
            return FallbackSpeechEngine(primary: primary, fallback: fallback)
        }
        if item.projectId != nil {
            return AppleSpeechEngine(voiceIdentifier: appleVoice, rate: engineRate)
        }
        return nil
    }

    #if os(macOS)
    func currentBlockers() -> [String] {
        var blockers = AudioActivityMonitor.activeDeferListBundleIDs()
        if AudioActivityMonitor.isAnyProcessUsingMicrophone() {
            blockers.append("mic")
        }
        return blockers
    }
    #endif

    func onControlAction(_ action: HTTPRequestParser.ControlAction) {
        guard let settings = settingsRef else { return }
        relayControl(action: action, settings: settings)
    }

    func onAckReceived(projectId: String) {
        guard let settings = settingsRef else { return }
        relayAck(projectId: projectId, settings: settings)
    }

    private func relayAck(projectId: String, settings: SettingsManager) {
        let relayIDs = settings.activeSpeakers
        guard !relayIDs.isEmpty else { return }

        for peer in peerBrowser.peers {
            guard relayIDs.contains(peer.id), let baseURL = peer.baseURL else { continue }
            guard let url = URL(string: "\(baseURL)/ack") else { continue }

            let peerName = peer.name
            let payload: [String: Any] = ["project_id": projectId]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 2

            let request = req
            Task.detached {
                _ = try? await URLSession.shared.data(for: request)
                Log.network.info("Relayed ack to \(peerName, privacy: .public)")
            }
        }
    }

    // MARK: - Thin wrappers

    func readText(
        _ text: String,
        appState: AppState,
        settings: SettingsManager,
        audioOnlyOverride: Bool? = nil,
        engineOverride: (any SpeechEngine)? = nil,
        projectId: String? = nil
    ) async {
        queue.enqueue(
            text,
            appState: appState,
            settings: settings,
            audioOnlyOverride: audioOnlyOverride,
            engineOverride: engineOverride,
            projectId: projectId
        )
    }

    func togglePause() {
        queue.togglePause()
    }

    func stop() {
        queue.stop()
    }

    func setSpeed(_ speed: Float) {
        queue.setSpeed(speed)
    }

    func handleAck(projectId: String, appState: AppState) {
        queue.handleAck(projectId: projectId, appState: appState)
    }

    func handleControl(_ control: HTTPRequestParser.ControlRequest) {
        queue.handleControl(control, deviceID: deviceID)
    }

    /// Relay a control action to all relay peers.
    func relayControl(action: HTTPRequestParser.ControlAction, settings: SettingsManager) {
        let relayIDs = settings.activeSpeakers
        guard !relayIDs.isEmpty else { return }

        for peer in peerBrowser.peers {
            guard relayIDs.contains(peer.id), let baseURL = peer.baseURL else { continue }
            guard let url = URL(string: "\(baseURL)/control") else { continue }

            let peerName = peer.name
            let payload: [String: Any] = ["action": action.rawValue, "origin": deviceID]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 2

            let request = req
            Task.detached {
                _ = try? await URLSession.shared.data(for: request)
                Log.network.info("Relayed control \(action.rawValue, privacy: .public) to \(peerName, privacy: .public)")
            }
        }
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
