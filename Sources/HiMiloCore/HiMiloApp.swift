import os
import SwiftUI

public struct HiMiloLauncher {
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
            HiMiloApp.main()
        }
    }
}

struct HiMiloApp: App {
    @State private var appState = AppState()
    @State private var coordinator = AppCoordinator()

    init() {
        Log.app.info("App init, creating MenuBarExtra")
    }

    var body: some Scene {
        MenuBarExtra("HiMilo", systemImage: "waveform") {
            MenuBarView(
                appState: appState,
                onTogglePause: { coordinator.togglePause() },
                onStop: { coordinator.stop() },
                onStartListening: { coordinator.startListening(appState: appState) },
                onStopListening: { coordinator.stopListening() },
                onReadText: { text in await coordinator.readText(text, appState: appState) }
            )
            .task {
                await coordinator.handleCLILaunch(appState: appState)
            }
        }
    }
}

@Observable
@MainActor
final class AppCoordinator {
    private var networkListener: NetworkListener?
    private var activeSession: ReadingSession?

    func startListening(appState: AppState, port: UInt16? = nil) {
        let port = port ?? CLIContext.shared?.port ?? 4140
        let listener = NetworkListener(port: port, appState: appState)
        do {
            try listener.start { [weak self] text in
                await self?.readText(text, appState: appState)
            }
            self.networkListener = listener
        } catch {
            Log.app.error("Failed to start listener: \(error)")
        }
    }

    func stopListening() {
        networkListener?.stop()
        networkListener = nil
    }

    func readText(_ text: String, appState: AppState) async {
        activeSession?.stop()

        let session = ReadingSession(appState: appState)
        activeSession = session

        let voice = CLIContext.shared?.voice ?? "onyx"
        await session.start(text: text, voice: voice)
    }

    func togglePause() {
        activeSession?.togglePause()
    }

    func stop() {
        activeSession?.stop()
        activeSession = nil
    }

    func handleCLILaunch(appState: AppState) async {
        guard let context = CLIContext.shared else { return }

        // Small delay to let the app finish initializing
        try? await Task.sleep(for: .milliseconds(100))

        if context.listen {
            startListening(appState: appState, port: context.port)
        } else if let text = context.text {
            appState.audioOnly = context.audioOnly
            await readText(text, appState: appState)
        }
    }
}
