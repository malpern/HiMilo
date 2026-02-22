import AVFoundation
import SwiftUI
import VoxClawCore

struct iOSSettingsView: View {
    @Bindable var settings: SettingsManager
    let coordinator: iOSCoordinator
    let appState: AppState

    @State private var portText: String = ""

    private let openAIVoices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    var body: some View {
        Form {
            overlaySection
            voiceSection
            networkSection
        }
        .onAppear {
            portText = String(settings.networkListenerPort)
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section("Voice") {
            Picker("Engine", selection: $settings.voiceEngine) {
                Text("Apple").tag(VoiceEngineType.apple)
                Text("OpenAI").tag(VoiceEngineType.openai)
            }
            .pickerStyle(.segmented)

            if settings.voiceEngine == .openai {
                Picker("Voice", selection: $settings.openAIVoice) {
                    ForEach(openAIVoices, id: \.self) { voice in
                        Text(voice.capitalized).tag(voice)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Reading Style", text: $settings.readingStyle, prompt: Text("e.g. Read warmly"))
                    Text("Natural language instructions for voice style.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                apiKeySection
            }
        }
    }

    private var apiKeySection: some View {
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
                let ip = NetworkListener.localIPAddress() ?? "<ip>"
                Text("Listening on http://\(ip):\(settings.networkListenerPort)")
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
