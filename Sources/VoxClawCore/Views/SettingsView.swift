import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsManager
    @State private var copiedAgentHandoff = false

    var body: some View {
        Form {
            voiceSection

            if settings.voiceEngine == .apple {
                appleVoiceSection
            } else {
                openAISetupSection
            }

            playbackSection
            networkSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 460, height: settings.voiceEngine == .openai ? 700 : 620)
    }

    // MARK: - Voice Engine Picker

    @ViewBuilder
    private var voiceSection: some View {
        Section("Voice Engine") {
            VoiceOptionCard(
                title: "Built-in Voice",
                subtitle: "Uses your Mac's text-to-speech. Works instantly with no setup.",
                systemImage: "desktopcomputer",
                isSelected: settings.voiceEngine == .apple
            ) {
                settings.voiceEngine = .apple
            }

            VoiceOptionCard(
                title: "OpenAI Voice",
                subtitle: "Natural-sounding neural voices powered by OpenAI. Bring your own API key.",
                badge: "Higher Quality",
                systemImage: "waveform.circle",
                isSelected: settings.voiceEngine == .openai,
                samplePlayer: VoiceSamplePlayer()
            ) {
                settings.voiceEngine = .openai
            }
        }
    }

    // MARK: - Apple Voice

    private var appleVoiceSection: some View {
        Section("Apple Voice") {
            Picker("Voice", selection: appleVoiceBinding) {
                Text("System Default").tag("" as String)
                ForEach(availableAppleVoices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(voice.language))")
                        .tag(voice.identifier)
                }
            }
        }
    }

    // MARK: - OpenAI Setup

    @ViewBuilder
    private var openAISetupSection: some View {
        if settings.isOpenAIConfigured {
            Section("OpenAI Voice") {
                Picker("Voice", selection: $settings.openAIVoice) {
                    ForEach(openAIVoices, id: \.self) { voice in
                        Text(voice.capitalized).tag(voice)
                    }
                }

                HStack {
                    Label("API key saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Remove Key") {
                        settings.openAIAPIKey = ""
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        } else {
            Section("Connect OpenAI") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("To use OpenAI voices, paste your API key below.")
                        .font(.callout)

                    HStack(spacing: 4) {
                        Text("1.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Open platform.openai.com/api-keys",
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Text("2.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Create a new key and copy it")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("3.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Paste it here:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        SecureField("sk-...", text: $settings.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Paste") {
                            if let clip = NSPasteboard.general.string(forType: .string) {
                                settings.openAIAPIKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }

                    Text("Your key is stored in your Mac's Keychain and never leaves your device except to authenticate with OpenAI.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }

        Section {
            Text("When using OpenAI, your reading text is sent to OpenAI for processing. [Privacy Policy](https://openai.com/privacy)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section("Playback") {
            Toggle("Audio Only (no teleprompter overlay)", isOn: $settings.audioOnly)
        }
    }

    // MARK: - Network

    @ViewBuilder
    private var networkSection: some View {
        Section {
            Toggle("Listen for network requests", isOn: $settings.networkListenerEnabled)

            if settings.networkListenerEnabled {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("4140", value: $settings.networkListenerPort, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }

                if let ip = NetworkListener.localIPAddress() {
                    Text("curl -X POST http://\(ip):\(settings.networkListenerPort)/read -d 'Hello'")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Share this with your agent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(agentHandoffText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button(copiedAgentHandoff ? "Copied" : "Copy Agent Setup") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(agentHandoffText, forType: .string)
                            copiedAgentHandoff = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedAgentHandoff = false
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Includes website pointer, skill doc, and this Mac's URLs.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
        } header: {
            Text("Network")
        } footer: {
            Text("Accepts POST /read and GET /status. Useful for scripting and sending text from other machines.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
        }
    }

    // MARK: - Helpers

    private var appleVoiceBinding: Binding<String> {
        Binding(
            get: { settings.appleVoiceIdentifier ?? "" },
            set: { settings.appleVoiceIdentifier = $0.isEmpty ? nil : $0 }
        )
    }

    private var availableAppleVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    private var agentHandoffText: String {
        let localBase = "http://localhost:\(settings.networkListenerPort)"
        let lanIP = NetworkListener.localIPAddress()
        let speakURL = lanIP.map { "http://\($0):\(settings.networkListenerPort)" }
            ?? "http://<lan-ip>:\(settings.networkListenerPort)"
        let healthURL = "\(speakURL)/status"
        return """
        🦞 VoxClaw setup pointer:
        - Website: https://voxclaw.com/
        - Agent skill/API doc: https://github.com/malpern/VoxClaw/blob/main/SKILL.md
        - Agent contract:
          If this pointer includes health_url/speak_url, use them directly.
          Do not ask for LAN IP, mDNS, or discovery first.
          Call health_url now, then speak_url.
        - Gold path (always use this order):
          1) On VoxClaw Mac: curl -sS \(localBase)/status
          2) From agent host: curl -sS \(healthURL)
          3) Then speak with: \(speakURL)/read
        - Test speak:
          curl -X POST \(speakURL)/read -H 'Content-Type: application/json' -d '{"text":"Hello from OpenClaw"}'
        - Never auto-switch to .local hostnames. Use numeric LAN IP unless a human explicitly gives a .local target.
        - If LAN step fails but localhost works: check macOS Firewall allows VoxClaw incoming connections.
        """
    }

    private let openAIVoices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
}

// MARK: - Voice Sample Player

@MainActor
final class VoiceSamplePlayer: ObservableObject {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerDelegate?

    func togglePlayback() {
        if isPlaying {
            player?.stop()
            isPlaying = false
            return
        }

        guard let url = Bundle.module.url(forResource: "onyx-sample", withExtension: "mp3") else {
            Log.settings.error("Voice sample not found in bundle")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlayerDelegate { [weak self] in
                Task { @MainActor in self?.isPlaying = false }
            }
            playerDelegate = delegate
            player?.delegate = delegate
            player?.play()
            isPlaying = true
        } catch {
            Log.settings.error("Failed to play voice sample: \(error)")
        }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, Sendable {
    let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// MARK: - Voice Option Card

private struct VoiceOptionCard: View {
    let title: String
    let subtitle: String
    var badge: String? = nil
    let systemImage: String
    let isSelected: Bool
    var samplePlayer: VoiceSamplePlayer? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(.capsule)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let samplePlayer {
                        SamplePlayButton(player: samplePlayer)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                    .font(.title3)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sample Play Button

private struct SamplePlayButton: View {
    @ObservedObject var player: VoiceSamplePlayer

    var body: some View {
        Button {
            player.togglePlayback()
        } label: {
            Label(
                player.isPlaying ? "Stop Preview" : "Preview Voice",
                systemImage: player.isPlaying ? "stop.circle.fill" : "play.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}
