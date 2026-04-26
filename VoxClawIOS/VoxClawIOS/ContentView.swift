import SwiftUI
import VoxClawCore

struct ContentView: View {
    let appState: AppState
    let settings: SettingsManager
    let coordinator: iOSCoordinator

    @Environment(\.scenePhase) private var scenePhase

    private var showTeleprompter: Bool {
        appState.isActive || appState.queueActive
    }

    var body: some View {
        Group {
            if showTeleprompter {
                TeleprompterView(
                    appState: appState,
                    settings: settings,
                    onTogglePause: { coordinator.togglePause() },
                    onStop: { coordinator.stop() }
                )
                .opacity(appState.contentFadedOut ? 0 : 1)
            } else {
                WaitingView(settings: settings, coordinator: coordinator, appState: appState)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showTeleprompter)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                coordinator.enterBackground(settings: settings)
            case .active:
                coordinator.exitBackground()
            default:
                break
            }
        }
    }
}
