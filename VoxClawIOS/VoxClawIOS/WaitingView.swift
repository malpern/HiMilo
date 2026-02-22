import SwiftUI
import VoxClawCore

struct WaitingView: View {
    let settings: SettingsManager
    let coordinator: iOSCoordinator
    let appState: AppState

    @State private var showSettings = false
    @State private var copiedAgentSetup = false
    @State private var showInstructions = false

    private var networkBaseURL: String {
        let hostname = VoxClawCore.NetworkListener.localHostname()
        return "http://\(hostname):\(settings.networkListenerPort)"
    }

    private var agentHandoffText: String {
        let healthURL = "\(networkBaseURL)/status"
        let speakURL = "\(networkBaseURL)/read"
        return """
        \u{1F9DE} VoxClaw setup pointer:
        health_url: \(healthURL)
        speak_url: \(speakURL)

        Agent rules:
        1) GET health_url first.
        2) If status is ok, POST text to speak_url.
        3) Use these URLs exactly (no .local/discovery rewrite unless a human explicitly asks).

        Website: https://voxclaw.com/
        Skill doc: https://github.com/malpern/VoxClaw/blob/main/SKILL.md
        """
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
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

                    // Agent setup
                    agentSetupView

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                if appState.isListening {
                    eyeButton
                        .padding(20)
                }
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

    // MARK: - Agent Setup

    @ViewBuilder
    private var agentSetupView: some View {
        if appState.isListening {
            VStack(spacing: 12) {
                Text("Tell your agent how to use VoxClaw to get a voice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    UIPasteboard.general.string = agentHandoffText
                    withAnimation {
                        copiedAgentSetup = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            copiedAgentSetup = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("\u{1F9DE}")
                        Text(copiedAgentSetup ? "Copied!" : "Copy Agent Setup")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(copiedAgentSetup ? .green : .gray)

                if showInstructions {
                    Text(agentHandoffText)
                        .font(.system(.caption2, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private var eyeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showInstructions.toggle()
            }
        } label: {
            Image(systemName: showInstructions ? "eye" : "eye.slash")
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
            return appState.isListening ? "Listening for text..." : "Starting listener..."
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
