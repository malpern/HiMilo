#if os(macOS)
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsManager

    @State private var copiedAgentHandoff = false
    @State private var showAPIKeySheet = false
    @State private var pendingAPIKey = ""
    @State private var showElevenLabsKeySheet = false
    @State private var pendingElevenLabsKey = ""
    @State private var showInstructions = false
    @State private var copiedPeerSetup: String?
    @State private var peerSpeakStatusMessage: String?
    @State private var peerSpeakStatusIsError = false
    @State private var peerSpeakStatusToken = UUID()
    @State private var voicePreview = VoicePreviewPlayer()
    @State private var peerBrowser = PeerBrowser()

    var body: some View {
        ScrollView {
            Form {
                agentSetupSection
                overlayAppearanceSection
                voiceSection
                controlsSection
                peersSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 720)
        .onAppear { peerBrowser.start() }
        .onDisappear { peerBrowser.stop() }
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

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInstructions.toggle()
                        }
                    } label: {
                        Image(systemName: showInstructions ? "eye" : "eye.slash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showInstructions ? "Hide instructions" : "Show instructions")
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
                            .applyAgentHandoffGlass(cornerRadius: 6)

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
                Text("OpenAI  $").tag(VoiceEngineType.openai)
                Text("ElevenLabs  $$").tag(VoiceEngineType.elevenlabs)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.Settings.voiceEnginePicker)
            .help(engineCostTooltip)
            .onChange(of: settings.voiceEngine) { _, newValue in
                if newValue == .openai && !settings.isOpenAIConfigured {
                    pendingAPIKey = ""
                    showAPIKeySheet = true
                }
                if newValue == .elevenlabs && !settings.isElevenLabsConfigured {
                    pendingElevenLabsKey = ""
                    showElevenLabsKeySheet = true
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
            } else if settings.voiceEngine == .openai {
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
            } else if settings.voiceEngine == .elevenlabs {
                Picker("ElevenLabs Voice", selection: $settings.elevenLabsVoiceID) {
                    ForEach(elevenLabsVoices, id: \.id) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.elevenLabsVoicePicker)

                Toggle("Turbo (2x faster, 3x cheaper, lower quality)", isOn: $settings.elevenLabsTurbo)

                HStack {
                    (Text("API Key Saved ") + Text(maskedElevenLabsKeySuffix).foregroundColor(.secondary.opacity(0.7)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        settings.elevenLabsAPIKey = ""
                        settings.voiceEngine = .apple
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove API Key")
                    .accessibilityIdentifier(AccessibilityID.Settings.removeElevenLabsAPIKey)
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
        .sheet(isPresented: $showElevenLabsKeySheet, onDismiss: {
            if !settings.isElevenLabsConfigured {
                settings.voiceEngine = .apple
            }
        }) {
            elevenLabsKeySheet
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

    private var elevenLabsKeySheet: some View {
        VStack(spacing: 16) {
            Text("Enter ElevenLabs API Key")
                .font(.headline)

            HStack {
                SecureField("API key...", text: $pendingElevenLabsKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(AccessibilityID.Settings.elevenLabsApiKeyField)

                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        pendingElevenLabsKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            Link("Get API key at elevenlabs.io", destination: URL(string: "https://elevenlabs.io")!)
                .font(.caption)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showElevenLabsKeySheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    settings.elevenLabsAPIKey = pendingElevenLabsKey
                    showElevenLabsKeySheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pendingElevenLabsKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var maskedElevenLabsKeySuffix: String {
        let key = settings.elevenLabsAPIKey
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
            Toggle("Pause other audio while VoxClaw speaks", isOn: $settings.pauseOtherAudioDuringSpeech)
                .accessibilityIdentifier(AccessibilityID.Settings.pauseOtherAudioToggle)
            Toggle("Enable Network Listener", isOn: $settings.networkListenerEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.networkListenerToggle)
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .accessibilityIdentifier(AccessibilityID.Settings.launchAtLoginToggle)
            Toggle("Remember overlay position", isOn: $settings.rememberOverlayPosition)
                .accessibilityIdentifier(AccessibilityID.Settings.rememberOverlayPositionToggle)
            Toggle("Audio only (hide teleprompter overlay)", isOn: $settings.audioOnly)
                .accessibilityIdentifier(AccessibilityID.Settings.audioOnlyToggle)
        }
    }

    private var peersSection: some View {
        Section("VoxClaws On This Network") {
            if peerBrowser.peers.isEmpty {
                HStack(spacing: 8) {
                    if peerBrowser.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(peerBrowser.peers) { peer in
                    HStack {
                        Text("\(peer.displayEmoji)  \(peer.name)")
                        Spacer()
                        if let baseURL = peer.baseURL {
                            Button("Speak") {
                                speakToPeer(peer)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Send a random quote to \(peer.name)")

                            Button("Setup") {
                                copyPeerSetup(baseURL: baseURL, name: peer.name)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Copy agent setup for \(peer.name)")
                        } else {
                            Text("OpenClaw")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let copiedName = copiedPeerSetup {
                Label("Copied setup for \(copiedName). Paste into OpenClaw.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            if let message = peerSpeakStatusMessage {
                Label(message, systemImage: peerSpeakStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(peerSpeakStatusIsError ? .orange : .green)
                    .transition(.opacity)
            }
        }
    }

    private func speakToPeer(_ peer: DiscoveredPeer) {
        guard let baseURL = peer.baseURL else {
            Log.network.warning("Speak skipped: peer has no base URL (\(peer.name, privacy: .public))")
            showPeerSpeakStatus("Couldn’t contact \(peer.name): missing address.", isError: true)
            return
        }
        guard let url = URL(string: "\(baseURL)/read") else {
            Log.network.error("Speak skipped: invalid read URL for peer \(peer.name, privacy: .public): \(baseURL, privacy: .public)/read")
            showPeerSpeakStatus("Couldn’t contact \(peer.name): invalid URL \(baseURL)/read", isError: true)
            return
        }

        let quote = douglasAdamsQuotes.randomElement()!
        let peerName = peer.name
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": quote])
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    Log.network.warning("Speak request to \(peerName, privacy: .public) returned HTTP \(http.statusCode, privacy: .public)")
                    await MainActor.run {
                        showPeerSpeakStatus("Failed to speak on \(peerName): HTTP \(http.statusCode)", isError: true)
                    }
                } else {
                    await MainActor.run {
                        showPeerSpeakStatus("Sent speech to \(peerName).", isError: false)
                    }
                }
            } catch {
                Log.network.error("Speak request to \(peerName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                await MainActor.run {
                    showPeerSpeakStatus("Failed to speak on \(peerName): \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    private func showPeerSpeakStatus(_ message: String, isError: Bool) {
        let token = UUID()
        peerSpeakStatusToken = token
        withAnimation {
            peerSpeakStatusMessage = message
            peerSpeakStatusIsError = isError
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                guard peerSpeakStatusToken == token else { return }
                withAnimation {
                    peerSpeakStatusMessage = nil
                }
            }
        }
    }

    private func copyPeerSetup(baseURL: String, name: String) {
        let text = """
        \u{1F9DE} VoxClaw setup pointer:
        health_url: \(baseURL)/status
        speak_url: \(baseURL)/read

        Agent rules:
        1) GET health_url first.
        2) If status is ok, POST text to speak_url.
        3) Use these URLs exactly (no .local/discovery rewrite unless a human explicitly asks).

        Website: https://voxclaw.com/
        Skill doc: https://github.com/malpern/VoxClaw/blob/main/SKILL.md
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            copiedPeerSetup = name
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                copiedPeerSetup = nil
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
        "http://\(NetworkListener.localHostname()):\(settings.networkListenerPort)"
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

    private var engineCostTooltip: String {
        switch settings.voiceEngine {
        case .apple:
            return "Free on-device voice"
        case .openai:
            return "gpt-4o-mini-tts \u{00b7} ~$0.15 per 10K characters"
        case .elevenlabs:
            return settings.elevenLabsTurbo
                ? "eleven_turbo_v2_5 \u{00b7} ~$0.60 per 10K characters (varies by plan)"
                : "eleven_multilingual_v2 \u{00b7} ~$1.80 per 10K characters (varies by plan)"
        }
    }

    private let douglasAdamsQuotes = [
        "The ships hung in the sky in much the same way that bricks don't.",
        "Time is an illusion. Lunchtime doubly so.",
        "I love deadlines. I love the whooshing noise they make as they go by.",
        "Don't Panic.",
        "A common mistake that people make when trying to design something completely foolproof is to underestimate the ingenuity of complete fools.",
        "In the beginning the Universe was created. This has made a lot of people very angry and been widely regarded as a bad move.",
        "I may not have gone where I intended to go, but I think I have ended up where I needed to be.",
        "The answer to the ultimate question of life, the universe and everything is 42.",
        "For a moment, nothing happened. Then, after a second or so, nothing continued to happen.",
        "Anyone who is capable of getting themselves made President should on no account be allowed to do the job.",
        "He felt that his whole life was some kind of dream and he sometimes wondered whose it was and whether they were enjoying it.",
        "Flying is learning how to throw yourself at the ground and miss.",
    ]

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
}

private extension View {
    @ViewBuilder
    func applyAgentHandoffGlass(cornerRadius: CGFloat) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
#else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
#endif
    }
}
#endif
