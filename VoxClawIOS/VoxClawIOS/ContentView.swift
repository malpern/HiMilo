import SwiftUI
import VoxClawCore

struct ContentView: View {
    let appState: AppState
    let settings: SettingsManager
    let coordinator: iOSCoordinator

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appState.isActive {
                TeleprompterView(
                    appState: appState,
                    settings: settings,
                    onTogglePause: { coordinator.togglePause() },
                    onStop: { coordinator.stop() }
                )
            } else {
                WaitingView(settings: settings, coordinator: coordinator, appState: appState)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isActive)
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
