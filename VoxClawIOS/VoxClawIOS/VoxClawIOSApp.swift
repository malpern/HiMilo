import AVFoundation
import SwiftUI
import VoxClawCore

@main
struct VoxClawIOSApp: App {
    @State private var appState = AppState()
    @State private var settings = SettingsManager()
    @State private var coordinator = iOSCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState, settings: settings, coordinator: coordinator)
                .task {
                    configureAudioSession()
                    #if targetEnvironment(simulator)
                    if settings.networkListenerPort == 4140 {
                        settings.networkListenerPort = 4141
                    }
                    #endif
                    coordinator.startListening(appState: appState, settings: settings)
                    coordinator.observeAudioInterruptions(appState: appState)
                }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AVAudioSession configuration failed: \(error)")
        }
    }
}
