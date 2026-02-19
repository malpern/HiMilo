import AVFoundation
import AppKit
import SwiftUI

// MARK: - Step Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome, voice, agentLocation, launchAtLogin, done
}

// MARK: - OnboardingView

struct OnboardingView: View {
    let settings: SettingsManager

    @State private var currentStep: OnboardingStep = .welcome
    @State private var transitionEdge: Edge = .trailing

    // Collected state
    @State private var apiKey = ""
    @State private var agentLocation: AgentLocation = .thisMac
    @State private var networkEnabled = false
    @State private var port: String = "4140"
    @State private var launchAtLogin = false

    // Audio
    @State private var narrator = OnboardingNarrator()
    @State private var demoPlayer = VoiceDemoPlayer()
    @State private var isMuted = false

    var body: some View {
        VStack(spacing: 0) {
            StepDots(current: currentStep)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStep(demoPlayer: demoPlayer)
                case .voice:
                    VoiceStep(apiKey: $apiKey, demoPlayer: demoPlayer)
                case .agentLocation:
                    AgentLocationStep(
                        location: $agentLocation,
                        networkEnabled: $networkEnabled,
                        port: $port
                    )
                case .launchAtLogin:
                    LaunchAtLoginStep(launchAtLogin: $launchAtLogin)
                case .done:
                    DoneStep(
                        hasAPIKey: !apiKey.isEmpty,
                        agentLocation: agentLocation,
                        networkEnabled: networkEnabled,
                        launchAtLogin: launchAtLogin
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.push(from: transitionEdge))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            NavBar(
                step: currentStep,
                isMuted: $isMuted,
                isSpeaking: demoPlayer.isPlaying || narrator.isSpeaking,
                onBack: goBack,
                onNext: goNext,
                onDone: handleComplete
            )
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 32)
        .frame(width: 500, height: 440)
        .task {
            // Auto-play demo on initial load (Welcome step)
            guard !isMuted else { return }
            demoPlayer.playDemo()
        }
        .onChange(of: currentStep) { _, newStep in
            handleStepChange(newStep)
        }
        .onChange(of: isMuted) { _, muted in
            if muted {
                demoPlayer.stop()
                narrator.stop()
            } else {
                // Replay current step audio on unmute
                handleStepChange(currentStep)
            }
        }
    }

    private func goBack() {
        stopAllAudio()
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        transitionEdge = .leading
        currentStep = prev
    }

    private func goNext() {
        stopAllAudio()
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        transitionEdge = .trailing
        currentStep = next
    }

    private func stopAllAudio() {
        demoPlayer.stop()
        narrator.stop()
    }

    private func handleComplete() {
        stopAllAudio()

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

    private func handleStepChange(_ step: OnboardingStep) {
        guard !isMuted else { return }

        switch step {
        case .welcome, .voice:
            demoPlayer.playDemo()
        case .agentLocation:
            narrator.speak(
                text: "OK so — where's your agent running? If it's on a different machine, like a Mac Mini, just flip on the network listener and VoxClaw picks it up. Super easy.",
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
        case .launchAtLogin:
            narrator.speak(
                text: "Alright — VoxClaw hangs out in your menu bar. You probably want it to start automatically when you log in, so your agent can talk to you whenever.",
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
        case .done:
            narrator.speak(
                text: "Boom — you're all set! VoxClaw is ready to go. Your agent finally has a voice. This is gonna be great.",
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
        }
    }
}

// MARK: - Agent Location

enum AgentLocation {
    case thisMac, remoteMachine
}

// MARK: - Step Dots

private struct StepDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Nav Bar

private struct NavBar: View {
    let step: OnboardingStep
    @Binding var isMuted: Bool
    let isSpeaking: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            if step != .welcome {
                Button("Back") { onBack() }
                    .buttonStyle(.glass)
            }

            Spacer()

            // Animated waveform when speaking
            if isSpeaking && !isMuted {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative.reversing, isActive: true)
                    .foregroundStyle(Color.accentColor)
                    .font(.body)
                    .transition(.opacity)
            }

            // Mute button
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(isMuted ? .secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute" : "Mute")
            .padding(.trailing, 8)

            if step == .welcome {
                Button("Get Started") { onNext() }
                    .buttonStyle(.glassProminent)
            } else if step == .done {
                Button("Done") { onDone() }
                    .buttonStyle(.glassProminent)
            } else {
                Button("Continue") { onNext() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Welcome Step

private struct WelcomeStep: View {
    let demoPlayer: VoiceDemoPlayer

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

            // Voice indicator showing which voice is speaking
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative.reversing, isActive: demoPlayer.isPlayingOpenAI)
                        .foregroundStyle(demoPlayer.isPlayingOpenAI ? Color.accentColor : Color.secondary.opacity(0.3))
                    Text("OpenAI")
                        .font(.caption)
                        .foregroundStyle(demoPlayer.isPlayingOpenAI ? Color.accentColor : .secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative.reversing, isActive: demoPlayer.isPlayingApple)
                        .foregroundStyle(demoPlayer.isPlayingApple ? Color.secondary : Color.secondary.opacity(0.3))
                    Text("Apple")
                        .font(.caption)
                        .foregroundStyle(demoPlayer.isPlayingApple ? .secondary : Color.secondary.opacity(0.3))
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Voice Step

private struct VoiceStep: View {
    @Binding var apiKey: String
    let demoPlayer: VoiceDemoPlayer

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text("Your Agent's Voice")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Hear the difference.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                // OpenAI voice row
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: demoPlayer.isPlayingOpenAI)
                        .foregroundStyle(demoPlayer.isPlayingOpenAI ? Color.accentColor : Color.secondary.opacity(0.3))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenAI Voice")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Natural, expressive — powered by your API key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Higher Quality")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(.capsule)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))

                // Apple voice row
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: demoPlayer.isPlayingApple)
                        .foregroundStyle(demoPlayer.isPlayingApple ? Color.secondary : Color.secondary.opacity(0.3))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in Voice")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Your Mac's text-to-speech — no setup needed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
            }

            // API Key field
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
                        Text("— optional, you can always add it later")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }
}

// MARK: - Agent Location Step

private struct AgentLocationStep: View {
    @Binding var location: AgentLocation
    @Binding var networkEnabled: Bool
    @Binding var port: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: location == .thisMac ? "laptopcomputer" : "network")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text("Where's Your OpenClaw?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("VoxClaw receives text from your agent and speaks it aloud.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                // This Mac option
                Button {
                    location = .thisMac
                    networkEnabled = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "laptopcomputer")
                            .font(.title2)
                            .foregroundStyle(location == .thisMac ? Color.accentColor : .secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("This Mac")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Agent runs locally — no network needed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: location == .thisMac ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(location == .thisMac ? Color.accentColor : Color.secondary.opacity(0.3))
                            .font(.title3)
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))

                // Remote machine option
                Button {
                    location = .remoteMachine
                    networkEnabled = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.title2)
                            .foregroundStyle(location == .remoteMachine ? Color.accentColor : .secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Another Machine")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Agent sends text over the network")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: location == .remoteMachine ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(location == .remoteMachine ? Color.accentColor : Color.secondary.opacity(0.3))
                            .font(.title3)
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
            }

            if location == .remoteMachine {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable network listener", isOn: $networkEnabled)

                    if networkEnabled {
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField("4140", text: $port)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                        }
                    }
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Launch at Login Step

private struct LaunchAtLoginStep: View {
    @Binding var launchAtLogin: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sunrise.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Stay Ready")
                .font(.title2)
                .fontWeight(.semibold)

            Text("VoxClaw lives in your menu bar.\nStart it automatically when you log in.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at Login", isOn: $launchAtLogin)

                Text("Your agent can speak the moment your Mac is ready.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }
}

// MARK: - Done Step

private struct DoneStep: View {
    let hasAPIKey: Bool
    let agentLocation: AgentLocation
    let networkEnabled: Bool
    let launchAtLogin: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set")
                .font(.title2)
                .fontWeight(.semibold)

            Text("VoxClaw is ready to give your agent a voice.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                SummaryRow(
                    icon: "speaker.wave.2.fill",
                    label: "Voice",
                    value: hasAPIKey ? "OpenAI" : "Built-in (Apple)"
                )
                SummaryRow(
                    icon: agentLocation == .thisMac ? "laptopcomputer" : "network",
                    label: "Agent",
                    value: agentLocation == .thisMac ? "This Mac" : "Remote"
                )
                if networkEnabled {
                    SummaryRow(
                        icon: "antenna.radiowaves.left.and.right",
                        label: "Listener",
                        value: "Enabled"
                    )
                }
                SummaryRow(
                    icon: "sunrise.fill",
                    label: "Launch at Login",
                    value: launchAtLogin ? "On" : "Off"
                )
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }
}

private struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}

// MARK: - Voice Demo Player

@MainActor @Observable
final class VoiceDemoPlayer {
    var isPlayingOpenAI = false
    var isPlayingApple = false
    var isPlaying: Bool { isPlayingOpenAI || isPlayingApple }

    private var player: AVAudioPlayer?
    private var playerDelegate: AudioFinishDelegate?
    private var synthesizer = AVSpeechSynthesizer()
    private var synthDelegate: SynthFinishDelegate?

    private let appleDemoText = "Or you could listen to me instead. The built-in Mac voice. I work, but... I kind of suck. You may want that OpenAI key."

    func playDemo() {
        stop()
        playOpenAI()
    }

    func stop() {
        player?.stop()
        player = nil
        playerDelegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPlayingOpenAI = false
        isPlayingApple = false
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
            Task { @MainActor in self?.isPlayingApple = false }
        }
        synthDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
        isPlayingApple = true
    }
}

// MARK: - OnboardingNarrator

@MainActor @Observable
final class OnboardingNarrator: NSObject {
    var isSpeaking = false

    private var player: AVAudioPlayer?
    private var playerDelegate: AudioFinishDelegate?
    private var synthesizer = AVSpeechSynthesizer()
    private var synthDelegate: SynthFinishDelegate?
    private var fetchTask: Task<Void, Never>?

    func speak(text: String, apiKey: String?) {
        stop()

        if let apiKey, !apiKey.isEmpty {
            speakWithOpenAI(text: text, apiKey: apiKey)
        } else {
            speakWithApple(text: text)
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
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
                    "instructions": "You are a guy casually talking to a friend, super excited to show them this thing you found. Speak like a real human — use vocal fry, vary your pitch a lot, speed up when excited, slow down for emphasis. Sound genuinely stoked. Do NOT sound like an AI or a narrator. Sound like a real dude on a podcast who just discovered something awesome.",
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    Log.onboarding.error("Narrator OpenAI error, falling back to Apple")
                    speakWithApple(text: text)
                    return
                }

                player = try AVAudioPlayer(data: data)
                let delegate = AudioFinishDelegate { [weak self] in
                    Task { @MainActor in self?.isSpeaking = false }
                }
                playerDelegate = delegate
                player?.delegate = delegate
                player?.play()
            } catch {
                guard !Task.isCancelled else { return }
                Log.onboarding.error("Narrator fetch error: \(error), falling back to Apple")
                speakWithApple(text: text)
            }
        }
    }

    private func speakWithApple(text: String) {
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        let delegate = SynthFinishDelegate { [weak self] in
            Task { @MainActor in self?.isSpeaking = false }
        }
        synthDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
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
