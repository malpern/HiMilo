import AVFoundation
import AppKit
import SwiftUI

// MARK: - Step Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome, apiKey, agentLocation, done
}

// MARK: - OnboardingView

struct OnboardingView: View {
    let settings: SettingsManager

    @State private var currentStep: OnboardingStep = .welcome
    @State private var stepIndex = 0
    @State private var transitionEdge: Edge = .trailing

    // Collected state
    @State private var apiKey = ""
    @State private var hasExistingKey = false
    @State private var agentLocation: AgentLocation = .thisMac
    @State private var networkEnabled = false
    @State private var port: String = "4140"
    @State private var launchAtLogin = true

    // Audio
    @State private var narrator = OnboardingNarrator()
    @State private var demoPlayer = VoiceDemoPlayer()
    @State private var isPaused = false

    private var steps: [OnboardingStep] {
        if hasExistingKey {
            return [.welcome, .done]
        } else {
            return [.welcome, .apiKey, .agentLocation, .done]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStep(demoPlayer: demoPlayer, hasExistingKey: hasExistingKey, narrator: narrator)
                case .apiKey:
                    APIKeyStep(apiKey: $apiKey)
                case .agentLocation:
                    AgentLocationStep(
                        location: $agentLocation,
                        networkEnabled: $networkEnabled,
                        port: $port,
                        launchAtLogin: $launchAtLogin
                    )
                case .done:
                    SuccessStep(
                        isRemote: agentLocation == .remoteMachine,
                        port: port
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.push(from: transitionEdge))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            NavBar(
                step: currentStep,
                isPaused: $isPaused,
                isFirstStep: stepIndex == 0,
                isRemoteDoneStep: currentStep == .done && agentLocation == .remoteMachine,
                onBack: goBack,
                onNext: goNext,
                onDone: handleComplete
            )
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 32)
        .frame(width: 500, height: 440)
        .task {
            demoPlayer.pauseExternalAudioDuringSpeech = settings.pauseOtherAudioDuringSpeech
            narrator.pauseExternalAudioDuringSpeech = settings.pauseOtherAudioDuringSpeech

            // Short flow when a key is already saved in keychain.
            let existingKey = (try? KeychainHelper.readFromKeychain()) ?? settings.openAIAPIKey
            let isPersistedKey = !existingKey.isEmpty

            if isPersistedKey {
                apiKey = existingKey
                hasExistingKey = true
                Log.onboarding.info("Existing API key found in keychain, using short flow")
                narrator.speak(
                    text: "Hey! Welcome to VoxClaw — your agent can finally talk! Let's go!",
                    apiKey: existingKey
                )
            } else {
                hasExistingKey = false
                demoPlayer.playDemo()
            }
        }
        .onChange(of: narrator.didFailOpenAI) { _, failed in
            if failed && hasExistingKey {
                Log.onboarding.info("OpenAI narrator failed, switching to full onboarding flow")
                hasExistingKey = false
                narrator.stop()
                demoPlayer.playDemo()
            }
        }
        .onChange(of: currentStep) { _, newStep in
            handleStepChange(newStep)
        }
        .onChange(of: apiKey) { _, newKey in
            // Persist key to keychain immediately so it survives window close
            if !newKey.isEmpty {
                settings.openAIAPIKey = newKey
                // Auto-advance when a valid-looking key is entered on the API key step
                if currentStep == .apiKey && newKey.hasPrefix("sk-") && newKey.count > 20 {
                    goNext()
                }
            }
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                demoPlayer.pause()
                narrator.pause()
            } else {
                demoPlayer.resume()
                narrator.resume()
            }
        }
    }

    private func goBack() {
        stopAllAudio()
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        transitionEdge = .leading
        currentStep = steps[stepIndex]
    }

    private func goNext() {
        stopAllAudio()
        guard stepIndex < steps.count - 1 else { return }
        stepIndex += 1
        transitionEdge = .trailing
        currentStep = steps[stepIndex]
    }

    private func stopAllAudio() {
        demoPlayer.stop()
        narrator.stop()
    }

    private func handleComplete() {
        stopAllAudio()

        if agentLocation == .remoteMachine {
            let handoff = makeAgentHandoffText(port: port)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(handoff, forType: .string)
        }

        if !apiKey.isEmpty {
            settings.openAIAPIKey = apiKey
            settings.voiceEngine = .openai
        }
        if agentLocation == .remoteMachine && networkEnabled {
            settings.networkListenerEnabled = true
            if let p = UInt16(port), p > 0 {
                settings.networkListenerPort = p
            }
        }
        settings.launchAtLogin = launchAtLogin
        settings.hasCompletedOnboarding = true

        Log.onboarding.info("Onboarding completed")
        NSApp.keyWindow?.close()
    }

    private func makeAgentHandoffText(port: String) -> String {
        let lanIP = NetworkListener.localIPAddress()
        let baseURL = lanIP.map { "http://\($0):\(port)" }
            ?? "http://<lan-ip>:\(port)"
        let healthURL = "\(baseURL)/status"
        let speakURL = "\(baseURL)/read"
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

    private func handleStepChange(_ step: OnboardingStep) {
        isPaused = false

        switch step {
        case .welcome:
            if hasExistingKey {
                narrator.speak(
                    text: "Hey! Welcome to VoxClaw — your agent can finally talk! Let's go!",
                    apiKey: apiKey
                )
            } else {
                demoPlayer.playDemo()
            }
        case .apiKey, .agentLocation:
            break
        case .done:
            narrator.speak(
                text: "Let's F-ing go!",
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
        }
    }
}

// MARK: - Step Dots

private struct StepDots: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Nav Bar

private struct NavBar: View {
    let step: OnboardingStep
    @Binding var isPaused: Bool
    let isFirstStep: Bool
    let isRemoteDoneStep: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            if !isFirstStep && step != .done {
#if compiler(>=6.2)
                if #available(macOS 26, *) {
                    Button("Back") { onBack() }
                        .buttonStyle(.glass)
                } else {
                    Button("Back") { onBack() }
                }
#else
                Button("Back") { onBack() }
#endif
            }

            Spacer()

            // Play/pause button — only on steps with audio
            if step == .welcome {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .onTapGesture { isPaused.toggle() }
                    .help(isPaused ? "Resume" : "Pause")
                    .padding(.trailing, 8)
            }

            if isFirstStep {
                prominentActionButton(title: "Get Started", action: onNext)
            } else if step == .done {
                prominentActionButton(
                    title: isRemoteDoneStep ? "Copy Setup & Finish" : "Done",
                    action: onDone
                )
            } else {
                prominentActionButton(title: "Continue", action: onNext)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func prominentActionButton(title: String, action: @escaping () -> Void) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            Button(title, action: action)
                .buttonStyle(.glassProminent)
        } else {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
        }
#else
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
#endif
    }
}

// MARK: - Welcome Step

private struct WelcomeStep: View {
    let demoPlayer: VoiceDemoPlayer
    let hasExistingKey: Bool
    let narrator: OnboardingNarrator

    var body: some View {
        VStack(spacing: 16) {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 192, height: 192)
            }

            Text("Welcome to VoxClaw")
                .font(.title)
                .fontWeight(.bold)

            Text("Give your OpenClaw agent a voice,\nright here on your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if hasExistingKey {
                // Existing key — just show a single waveform for live OpenAI speech
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative.reversing, isActive: narrator.isSpeaking)
                        .foregroundStyle(narrator.isSpeaking ? Color.accentColor : Color.secondary.opacity(0.3))
                    Text("OpenAI")
                        .font(.caption)
                        .fontWeight(narrator.isSpeaking ? .bold : .regular)
                        .foregroundStyle(narrator.isSpeaking ? Color.accentColor : .secondary)
                }
                .padding(.top, 4)
            } else {
                // No key — show both voice indicators for bundled demo
                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative.reversing, isActive: demoPlayer.isPlayingOpenAI)
                            .foregroundStyle(demoPlayer.isPlayingOpenAI ? Color.accentColor : Color.secondary.opacity(0.3))
                        Text("OpenAI")
                            .font(.caption)
                            .fontWeight(demoPlayer.isPlayingOpenAI ? .bold : .regular)
                            .foregroundStyle(demoPlayer.isPlayingOpenAI ? Color.accentColor : .secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative.reversing, isActive: demoPlayer.isPlayingApple)
                            .foregroundStyle(demoPlayer.isPlayingApple ? Color.accentColor : Color.secondary.opacity(0.3))
                        Text("Apple")
                            .font(.caption)
                            .fontWeight(demoPlayer.isPlayingApple ? .bold : .regular)
                            .foregroundStyle(demoPlayer.isPlayingApple ? Color.accentColor : .secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - API Key Step

private struct APIKeyStep: View {
    @Binding var apiKey: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text("Add Your OpenAI Key")
                .font(.title2)
                .fontWeight(.semibold)

            Text("For the natural voice you just heard,\nadd your OpenAI API key. Or skip to use\nyour Mac's built-in voice instead.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                if !apiKey.isEmpty {
                    HStack {
                        Label("API key saved", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove") {
                            apiKey = ""
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                } else {
                    HStack {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Paste") {
                            if let clip = NSPasteboard.general.string(forType: .string) {
                                apiKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Link("Get an API key",
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                        Text("— optional, you can always add it later in Settings")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .modifier(GlassBackgroundModifier())
        }
    }
}

// MARK: - Agent Location

enum AgentLocation {
    case thisMac, remoteMachine
}

// MARK: - Agent Location Step

private struct AgentLocationStep: View {
    @Binding var location: AgentLocation
    @Binding var networkEnabled: Bool
    @Binding var port: String
    @Binding var launchAtLogin: Bool

    @State private var isEditingPort = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: location == .thisMac ? "laptopcomputer" : "network")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))

            Text("Where's Your OpenClaw?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("VoxClaw receives text from your agent and speaks it aloud.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                locationRow(
                    icon: "laptopcomputer",
                    title: "This Mac",
                    subtitle: "Agent runs locally — no network needed",
                    selected: location == .thisMac
                ) {
                    location = .thisMac
                    networkEnabled = false
                }

                locationRow(
                    icon: "network",
                    title: "Another Machine",
                    subtitle: "Network listener on — agent sends text over the network",
                    selected: location == .remoteMachine
                ) {
                    location = .remoteMachine
                    networkEnabled = true
                }
            }

            HStack {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Spacer()
            }
        }
        .alert("Network Listener Port", isPresented: $isEditingPort) {
            TextField("Port", text: $port)
            Button("OK") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the port VoxClaw should listen on.")
        }
    }

    private func locationRow(
        icon: String,
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.3))
                    .font(.title3)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(GlassInteractiveModifier())
    }
}

// MARK: - Success Step

private struct SuccessStep: View {
    let isRemote: Bool
    let port: String

    private var agentHandoffText: String {
        let lanIP = NetworkListener.localIPAddress()
        let baseURL = lanIP.map { "http://\($0):\(port)" }
            ?? "http://<lan-ip>:\(port)"
        let healthURL = "\(baseURL)/status"
        let speakURL = "\(baseURL)/read"
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set")
                .font(.title)
                .fontWeight(.bold)

            Text("VoxClaw is ready to give your agent a voice.")
                .font(.body)
                .foregroundStyle(.secondary)

            if isRemote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Send text from your agent:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("curl -X POST http://<lan-ip>:\(port)/read \\\n  -d '{\"text\": \"Hello from the network\"}'")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Or paste this setup pointer to your agent:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(agentHandoffText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Voice Demo Player

@MainActor @Observable
final class VoiceDemoPlayer {
    var isPlayingOpenAI = false
    var isPlayingApple = false
    var isPlaying: Bool { isPlayingOpenAI || isPlayingApple }
    var pauseExternalAudioDuringSpeech = true

    private var player: AVAudioPlayer?
    private var playerDelegate: AudioFinishDelegate?
    private var synthesizer = AVSpeechSynthesizer()
    private var synthDelegate: SynthFinishDelegate?
    private let playbackController: any ExternalPlaybackControlling = ExternalPlaybackController()
    private var pausedExternalAudio = false

    private let appleDemoText = "Or you could listen to me instead. The built-in Mac voice. I work, but... I kind of suck. You may want that OpenAI key."

    func playDemo() {
        stop()
        beginExternalAudioPauseWindow()
        playOpenAI()
    }

    func pause() {
        if isPlayingOpenAI {
            player?.pause()
        } else if isPlayingApple {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    func resume() {
        if isPlayingOpenAI {
            player?.play()
        } else if isPlayingApple {
            synthesizer.continueSpeaking()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playerDelegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPlayingOpenAI = false
        isPlayingApple = false
        endExternalAudioPauseWindow()
    }

    private func playOpenAI() {
        guard let url = Bundle.module.url(forResource: "onboarding-openai", withExtension: "mp3") else {
            Log.onboarding.error("Onboarding OpenAI sample not found in bundle")
            playApple()
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            let delegate = AudioFinishDelegate { [weak self] in
                Task { @MainActor in
                    self?.isPlayingOpenAI = false
                    self?.playApple()
                }
            }
            playerDelegate = delegate
            player?.delegate = delegate
            player?.play()
            isPlayingOpenAI = true
        } catch {
            Log.onboarding.error("Failed to play OpenAI sample: \(error)")
            playApple()
        }
    }

    private func playApple() {
        let utterance = AVSpeechUtterance(string: appleDemoText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        let delegate = SynthFinishDelegate { [weak self] in
            Task { @MainActor in
                self?.isPlayingApple = false
                self?.endExternalAudioPauseWindow()
            }
        }
        synthDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
        isPlayingApple = true
    }

    private func beginExternalAudioPauseWindow() {
        guard pauseExternalAudioDuringSpeech else { return }
        pausedExternalAudio = playbackController.pauseIfPlaying()
    }

    private func endExternalAudioPauseWindow() {
        guard pausedExternalAudio else { return }
        playbackController.resumePaused()
        pausedExternalAudio = false
    }
}

// MARK: - OnboardingNarrator

@MainActor @Observable
final class OnboardingNarrator: NSObject {
    var isSpeaking = false
    var didFailOpenAI = false
    var pauseExternalAudioDuringSpeech = true

    private var player: AVAudioPlayer?
    private var playerDelegate: AudioFinishDelegate?
    private var synthesizer = AVSpeechSynthesizer()
    private var synthDelegate: SynthFinishDelegate?
    private var fetchTask: Task<Void, Never>?
    private let playbackController: any ExternalPlaybackControlling = ExternalPlaybackController()
    private var pausedExternalAudio = false

    func speak(text: String, apiKey: String?) {
        stop()
        didFailOpenAI = false
        beginExternalAudioPauseWindow()

        if let apiKey, !apiKey.isEmpty {
            speakWithOpenAI(text: text, apiKey: apiKey)
        } else {
            speakWithApple(text: text)
        }
    }

    func pause() {
        if player?.isPlaying == true {
            player?.pause()
        } else {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    func resume() {
        if let player, !player.isPlaying, player.currentTime > 0 {
            player.play()
        } else {
            synthesizer.continueSpeaking()
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        endExternalAudioPauseWindow()
    }

    private func speakWithOpenAI(text: String, apiKey: String) {
        isSpeaking = true

        fetchTask = Task {
            do {
                guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "model": "gpt-4o-mini-tts",
                    "input": text,
                    "voice": "onyx",
                    "response_format": "mp3",
                    "instructions": "You are genuinely PUMPED. Like a best friend who just watched someone nail something incredible. Big grin on your face, voice rising with real excitement — not screaming, but that infectious energy where you can HEAR the smile. Punchy, fast, celebratory. Think sports commentator after a buzzer-beater, or a hype man gassing up his crew. Let the energy BUILD through the line and absolutely PEAK on the last two words.",
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    Log.onboarding.error("Narrator OpenAI error (status \(statusCode, privacy: .public)), falling back to Apple")
                    didFailOpenAI = true
                    speakWithApple(text: text)
                    return
                }

                player = try AVAudioPlayer(data: data)
                let delegate = AudioFinishDelegate { [weak self] in
                    Task { @MainActor in
                        self?.isSpeaking = false
                        self?.endExternalAudioPauseWindow()
                    }
                }
                playerDelegate = delegate
                player?.delegate = delegate
                player?.play()
            } catch {
                guard !Task.isCancelled else { return }
                Log.onboarding.error("Narrator fetch error: \(error), falling back to Apple")
                didFailOpenAI = true
                speakWithApple(text: text)
            }
        }
    }

    private func speakWithApple(text: String) {
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        let delegate = SynthFinishDelegate { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
                self?.endExternalAudioPauseWindow()
            }
        }
        synthDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
    }

    private func beginExternalAudioPauseWindow() {
        guard pauseExternalAudioDuringSpeech else { return }
        pausedExternalAudio = playbackController.pauseIfPlaying()
    }

    private func endExternalAudioPauseWindow() {
        guard pausedExternalAudio else { return }
        playbackController.resumePaused()
        pausedExternalAudio = false
    }
}

// MARK: - Glass Compatibility Modifiers

private struct GlassBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 10))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
#else
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
#endif
    }
}

private struct GlassInteractiveModifier: ViewModifier {
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
#else
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
#endif
    }
}

// MARK: - Audio Delegates

private final class AudioFinishDelegate: NSObject, AVAudioPlayerDelegate, Sendable {
    let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

private final class SynthFinishDelegate: NSObject, AVSpeechSynthesizerDelegate, Sendable {
    let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
}
