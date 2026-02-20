import AppKit
import os
import SwiftUI

public struct VoxClawLauncher {
    @MainActor public static func main() {
        let args = ProcessInfo.processInfo.arguments
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
            Log.app.info("entering menuBar mode")
            VoxClawApp.main()
        }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !SharedApp.settings.hasCompletedOnboarding else { return }

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
}

struct VoxClawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        }

        Window("Settings", id: "settings") {
            SettingsView(settings: settings)
        }
        .defaultSize(width: 440, height: 420)

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

    func startListening(appState: AppState, settings: SettingsManager, port: UInt16? = nil) {
        let port = port ?? CLIContext.shared?.port ?? 4140
        let listener = NetworkListener(port: port, appState: appState)
        do {
            try listener.start { [weak self] request in
                await self?.handleReadRequest(request, appState: appState, settings: settings)
            }
            self.networkListener = listener
        } catch {
            Log.app.error("Failed to start listener: \(error)")
        }
    }

    private func handleReadRequest(_ request: ReadRequest, appState: AppState, settings: SettingsManager) async {
        // Build engine with request overrides, falling back to settings defaults
        let voice = request.voice ?? settings.openAIVoice
        let rate = request.rate ?? 1.0
        var engine: (any SpeechEngine)?
        if !settings.openAIAPIKey.isEmpty {
            engine = OpenAISpeechEngine(apiKey: settings.openAIAPIKey, voice: voice, speed: rate)
        } else if request.rate != nil {
            engine = AppleSpeechEngine(rate: rate)
        }
        await readText(request.text, appState: appState, settings: settings, engineOverride: engine)
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
        engineOverride: (any SpeechEngine)? = nil
    ) async {
        activeSession?.stop()
        appState.audioOnly = audioOnlyOverride ?? settings.audioOnly
        let engine = engineOverride ?? settings.createEngine()
        let session = ReadingSession(appState: appState, engine: engine)
        activeSession = session
        await session.start(text: text)
    }

    func togglePause() {
        activeSession?.togglePause()
    }

    func stop() {
        activeSession?.stop()
        activeSession = nil
    }

    func handleCLILaunch(appState: AppState, settings: SettingsManager) async {
        guard let context = CLIContext.shared else { return }

        // Small delay to let the app finish initializing
        try? await Task.sleep(for: .milliseconds(100))

        if context.listen {
            startListening(appState: appState, settings: settings, port: context.port)
        } else if let text = context.text {
            let engine: any SpeechEngine
            if let apiKey = try? KeychainHelper.readAPIKey() {
                engine = OpenAISpeechEngine(apiKey: apiKey, voice: context.voice, speed: context.rate)
            } else {
                engine = AppleSpeechEngine(rate: context.rate)
            }
            await readText(text, appState: appState, settings: settings,
                           audioOnlyOverride: context.audioOnly, engineOverride: engine)
        }
    }
}
