import SwiftUI
import VoxClawCore

struct WaitingView: View {
    let settings: SettingsManager
    let coordinator: iOSCoordinator
    let appState: AppState

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // App logo
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27))

                Text("VoxClaw")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Status indicator
                statusView

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    iOSSettingsView(settings: settings, coordinator: coordinator, appState: appState)
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showSettings = false
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch appState.sessionState {
        case .idle:
            return appState.isListening ? .green : .orange
        case .loading:
            return .blue
        case .playing:
            return .blue
        case .paused:
            return .yellow
        case .finished:
            return .green
        }
    }

    private var statusText: String {
        switch appState.sessionState {
        case .idle:
            return appState.isListening ? "Listening for text" : "Starting listener..."
        case .loading:
            return "Receiving text..."
        case .playing:
            return "Speaking..."
        case .paused:
            return "Paused"
        case .finished:
            return "Finished"
        }
    }

}
