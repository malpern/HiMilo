import AVFoundation
import SwiftUI
import VoxClawCore

struct iOSSettingsView: View {
    @Bindable var settings: SettingsManager
    let coordinator: iOSCoordinator
    let appState: AppState

    @State private var portText: String = ""
    @State private var voicePreview = VoicePreviewPlayer()
    @State private var copiedAgentHandoff = false
    @State private var showInstructions = false

    private let openAIVoices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
    private let elevenLabsVoices: [(id: String, name: String)] = [
        ("JBFqnCBsd6RMkjVDRZzb", "George"),
        ("21m00Tcm4TlvDq8ikWAM", "Rachel"),
        ("pNInz6obpgDQGcFmaJgB", "Adam"),
        ("ThT5KcBeYPX3keUQqHPh", "Dorothy"),
        ("2EiwWnXFnvU5JabPnv8n", "Clyde"),
        ("CYw3kZ02Hs0563khs1Fj", "Dave"),
        ("D38z5RcWu1voky8WS1ja", "Fin"),
        ("z9fAnlkpzviPz146aGWa", "Glinda"),
    ]

    var body: some View {
        Form {
            agentSetupSection
            overlaySection
            voiceSection
            networkSection
        }
        .onAppear {
            portText = String(settings.networkListenerPort)
        }
    }

    // MARK: - Agent Setup

    private var networkBaseURL: String {
        let hostname = NetworkListener.localHostname()
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

    private var agentSetupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tell your agent how to use VoxClaw to get a voice.")
                    .font(.headline)

                HStack(alignment: .center, spacing: 12) {
                    Button {
                        UIPasteboard.general.string = agentHandoffText
                        copiedAgentHandoff = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copiedAgentHandoff = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("\u{1F9DE}")
                            Text(copiedAgentHandoff ? "Copied!" : "Copy Agent Setup")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.86, green: 0.16, blue: 0.14))

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInstructions.toggle()
                        }
                    } label: {
                        Image(systemName: showInstructions ? "eye" : "eye.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                if copiedAgentHandoff {
                    Label("Copied. Paste this into OpenClaw.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if showInstructions {
                    Text(agentHandoffText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section("Voice") {
            Picker("Engine", selection: $settings.voiceEngine) {
                Text("Apple").tag(VoiceEngineType.apple)
                Text("OpenAI").tag(VoiceEngineType.openai)
                Text("ElevenLabs").tag(VoiceEngineType.elevenlabs)
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.voiceEngine) { _, newValue in
                if newValue == .openai && !settings.isOpenAIConfigured {
                    // Stay on engine; user will enter key inline
                }
                if newValue == .elevenlabs && !settings.isElevenLabsConfigured {
                    // Stay on engine; user will enter key inline
                }
            }

            HStack {
                Text("Speed: \(settings.voiceSpeed, specifier: "%.1f")x")
                Spacer()
                SpeedSlider(speed: $settings.voiceSpeed)
                    .frame(maxWidth: .infinity)
                    .frame(maxWidth: 200)
            }

            if settings.voiceEngine == .openai {
                Picker("Voice", selection: $settings.openAIVoice) {
                    ForEach(openAIVoices, id: \.self) { voice in
                        Text(voice.capitalized).tag(voice)
                    }
                }
                .onChange(of: settings.openAIVoice) { _, newVoice in
                    guard settings.isOpenAIConfigured else { return }
                    voicePreview.play(
                        voice: newVoice,
                        apiKey: settings.openAIAPIKey,
                        instructions: nil
                    )
                }

                openAIKeySection
            } else if settings.voiceEngine == .elevenlabs {
                Picker("Voice", selection: $settings.elevenLabsVoiceID) {
                    ForEach(elevenLabsVoices, id: \.id) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }

                Toggle("Turbo (faster, cheaper, lower quality)", isOn: $settings.elevenLabsTurbo)

                elevenLabsKeySection
            }
        }
    }

    private var openAIKeySection: some View {
        Group {
            if settings.isOpenAIConfigured {
                HStack {
                    Label("API key saved", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        settings.openAIAPIKey = ""
                    }
                    .font(.caption)
                }
            } else {
                HStack {
                    SecureField("sk-...", text: $settings.openAIAPIKey)
                    Button("Paste") {
                        if let clip = UIPasteboard.general.string {
                            settings.openAIAPIKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }

                Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }
        }
    }

    private var elevenLabsKeySection: some View {
        Group {
            if settings.isElevenLabsConfigured {
                HStack {
                    Label("API key saved", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        settings.elevenLabsAPIKey = ""
                    }
                    .font(.caption)
                }
            } else {
                HStack {
                    SecureField("API key...", text: $settings.elevenLabsAPIKey)
                    Button("Paste") {
                        if let clip = UIPasteboard.general.string {
                            settings.elevenLabsAPIKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }

                Link("Get an API key", destination: URL(string: "https://elevenlabs.io")!)
                    .font(.caption)
            }
        }
    }

    // MARK: - Overlay

    private var overlaySection: some View {
        Section("Overlay Appearance") {
            OverlayPresetGallery(settings: settings, compact: true)
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        Section("Network Listener") {
            HStack {
                Text("Port")
                Spacer()
                TextField("4140", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onChange(of: portText) { _, newValue in
                        if let p = UInt16(newValue), p > 0 {
                            settings.networkListenerPort = p
                            coordinator.stopListening()
                            coordinator.startListening(appState: appState, settings: settings)
                        }
                    }
            }

            if appState.isListening {
                Text("\u{1F4F1}  \(NetworkListener.localComputerName()):\(settings.networkListenerPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Keep alive in background", isOn: $settings.backgroundKeepAlive)

            if settings.backgroundKeepAlive {
                Text("Plays silent audio to keep the listener active when backgrounded. Stops automatically after 30 minutes of inactivity.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
