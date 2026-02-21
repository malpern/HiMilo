import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsManager

    @State private var copiedAgentHandoff = false
    @State private var showOpenAISetup = false
    @State private var showInstructions = false

    var body: some View {
        ScrollView {
            Form {
                agentSetupSection
                voiceSection
                overlayAppearanceSection
                controlsSection
                readOnlyDataSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 720)
    }

    private var agentSetupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tell your agent how to use VoxClaw to get a voice.")
                    .font(.headline)

                HStack(alignment: .center, spacing: 12) {
                    Button {
                        if !settings.networkListenerEnabled {
                            settings.networkListenerEnabled = true
                        }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(agentHandoffText, forType: .string)
                        copiedAgentHandoff = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copiedAgentHandoff = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("🦞")
                            Text(primaryAgentActionTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(websiteRed)
                    .accessibilityIdentifier(AccessibilityID.Settings.copyAgentSetup)

                    Button(showInstructions ? "hide instructions" : "show instructions") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInstructions.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .underline()
                    .accessibilityIdentifier(AccessibilityID.Settings.showInstructions)
                }

                if copiedAgentHandoff {
                    Label("Copied. Paste this into OpenClaw.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if !settings.networkListenerEnabled {
                    Label("This will enable listener and copy setup text.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showInstructions {
                    Text(agentHandoffText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 6))
                }
            }
        }
    }

    private var voiceSection: some View {
        Section("Voice") {
            Picker("Engine", selection: $settings.voiceEngine) {
                Text("Apple").tag(VoiceEngineType.apple)
                Text("OpenAI").tag(VoiceEngineType.openai)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.Settings.voiceEnginePicker)

            if settings.voiceEngine == .apple {
                Picker("Apple Voice", selection: appleVoiceBinding) {
                    Text("System Default").tag("" as String)
                    ForEach(availableAppleVoices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.identifier)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.appleVoicePicker)
            } else {
                Picker("OpenAI Voice", selection: $settings.openAIVoice) {
                    ForEach(openAIVoices, id: \.self) { voice in
                        Text(voice.capitalized).tag(voice)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.openAIVoicePicker)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Reading Style", text: $settings.readingStyle, prompt: Text("e.g. Read warmly and conversationally"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(AccessibilityID.Settings.readingStyleField)
                    Text("Natural language instructions for OpenAI voice style. Leave empty for default.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("OpenAI Setup", isExpanded: $showOpenAISetup) {
                    VStack(alignment: .leading, spacing: 10) {
                        if settings.isOpenAIConfigured {
                            Label("API key saved in Keychain", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("No API key configured", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }

                        HStack {
                            SecureField("sk-...", text: $settings.openAIAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier(AccessibilityID.Settings.apiKeyField)

                            Button("Paste") {
                                if let clip = NSPasteboard.general.string(forType: .string) {
                                    settings.openAIAPIKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            .accessibilityIdentifier(AccessibilityID.Settings.pasteAPIKey)
                        }

                        HStack(spacing: 12) {
                            Link("Get API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                .accessibilityIdentifier(AccessibilityID.Settings.getAPIKeyLink)
                            if settings.isOpenAIConfigured {
                                Button("Remove Key", role: .destructive) {
                                    settings.openAIAPIKey = ""
                                }
                                .accessibilityIdentifier(AccessibilityID.Settings.removeAPIKey)
                            }
                        }

                        Text("Your key is stored in macOS Keychain.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private var overlayAppearanceSection: some View {
        Section("Overlay Appearance") {
            OverlayAppearanceSettingsView(settings: settings)
        }
    }

    private var controlsSection: some View {
        Section("Controls") {
            Toggle("Enable Network Listener", isOn: $settings.networkListenerEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.networkListenerToggle)
            Toggle("Pause other audio while VoxClaw speaks", isOn: $settings.pauseOtherAudioDuringSpeech)
                .accessibilityIdentifier(AccessibilityID.Settings.pauseOtherAudioToggle)
            Toggle("Audio only (hide teleprompter overlay)", isOn: $settings.audioOnly)
                .accessibilityIdentifier(AccessibilityID.Settings.audioOnlyToggle)
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .accessibilityIdentifier(AccessibilityID.Settings.launchAtLoginToggle)
        }
    }

    private var readOnlyDataSection: some View {
        Section("Read-Only Data") {
            copiableRow("Status URL", value: "\(networkBaseURL)/status")
            copiableRow("Speak URL", value: "\(networkBaseURL)/read")
        }
    }

    private func copiableRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
    }

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

    private var networkBaseURL: String {
        let lanIP = NetworkListener.localIPAddress()
        return lanIP.map { "http://\($0):\(settings.networkListenerPort)" }
            ?? "http://<lan-ip>:\(settings.networkListenerPort)"
    }

    private var primaryAgentActionTitle: String {
        settings.networkListenerEnabled ? "Copy Agent Setup" : "Enable Listener & Copy Setup"
    }

    private var websiteRed: Color {
        Color(red: 0.86, green: 0.16, blue: 0.14)
    }

    private var agentHandoffText: String {
        let healthURL = "\(networkBaseURL)/status"
        let speakURL = "\(networkBaseURL)/read"
        return """
        🦞 VoxClaw setup pointer:
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

    private let openAIVoices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
}
