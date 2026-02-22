#if os(macOS)
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsManager

    @State private var copiedAgentHandoff = false
    @State private var showAPIKeySheet = false
    @State private var pendingAPIKey = ""
    @State private var showInstructions = false
    @State private var voicePreview = VoicePreviewPlayer()

    var body: some View {
        ScrollView {
            Form {
                agentSetupSection
                overlayAppearanceSection
                voiceSection
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
                    ZStack(alignment: .topTrailing) {
                        Text(agentHandoffText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 6))

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(agentHandoffText, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                        .padding(8)
                    }
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
            .onChange(of: settings.voiceEngine) { _, newValue in
                if newValue == .openai && !settings.isOpenAIConfigured {
                    pendingAPIKey = ""
                    showAPIKeySheet = true
                }
            }

            HStack {
                Text("Speed: \(settings.voiceSpeed, specifier: "%.1f")x")
                Spacer()
                SpeedSlider(speed: $settings.voiceSpeed)
                    .frame(maxWidth: .infinity)
                    .frame(maxWidth: 180)
            }
            .accessibilityIdentifier(AccessibilityID.Settings.voiceEnginePicker + "Speed")

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
                .onChange(of: settings.openAIVoice) { _, newVoice in
                    guard settings.isOpenAIConfigured else { return }
                    voicePreview.play(
                        voice: newVoice,
                        apiKey: settings.openAIAPIKey,
                        instructions: nil
                    )
                }

                HStack {
                    (Text("API Key Saved ") + Text(maskedAPIKeySuffix).foregroundColor(.secondary.opacity(0.7)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.Settings.apiKeyDisplay)
                    Spacer()
                    Button {
                        settings.openAIAPIKey = ""
                        settings.voiceEngine = .apple
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove API Key")
                    .accessibilityIdentifier(AccessibilityID.Settings.removeAPIKey)
                }
            }
        }
        .sheet(isPresented: $showAPIKeySheet, onDismiss: {
            if !settings.isOpenAIConfigured {
                settings.voiceEngine = .apple
            }
        }) {
            apiKeySheet
        }
    }

    private var apiKeySheet: some View {
        VStack(spacing: 16) {
            Text("Enter OpenAI API Key")
                .font(.headline)

            HStack {
                SecureField("sk-...", text: $pendingAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(AccessibilityID.Settings.apiKeyField)

                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        pendingAPIKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.pasteAPIKey)
            }

            Link("Get API key at platform.openai.com", destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.caption)
                .accessibilityIdentifier(AccessibilityID.Settings.getAPIKeyLink)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showAPIKeySheet = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AccessibilityID.Settings.apiKeySheetCancel)

                Button("Save") {
                    settings.openAIAPIKey = pendingAPIKey
                    showAPIKeySheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier(AccessibilityID.Settings.apiKeySheetSave)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var maskedAPIKeySuffix: String {
        let key = settings.openAIAPIKey
        guard key.count >= 4 else { return "..." }
        return String(key.suffix(4))
    }

    private var overlayAppearanceSection: some View {
        Section {
            OverlayAppearanceSettingsView(settings: settings)
        }
    }

    private var controlsSection: some View {
        Section("Controls") {
            Toggle("Audio only (hide teleprompter overlay)", isOn: $settings.audioOnly)
                .accessibilityIdentifier(AccessibilityID.Settings.audioOnlyToggle)
            Toggle("Pause other audio while VoxClaw speaks", isOn: $settings.pauseOtherAudioDuringSpeech)
                .accessibilityIdentifier(AccessibilityID.Settings.pauseOtherAudioToggle)
            Toggle("Enable Network Listener", isOn: $settings.networkListenerEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.networkListenerToggle)
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .accessibilityIdentifier(AccessibilityID.Settings.launchAtLoginToggle)
            Toggle("Remember overlay position", isOn: $settings.rememberOverlayPosition)
                .accessibilityIdentifier(AccessibilityID.Settings.rememberOverlayPositionToggle)
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
#endif
