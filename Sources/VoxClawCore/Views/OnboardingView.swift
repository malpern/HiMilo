#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Step Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome, connectAgent, apiKey, done
}

// MARK: - OnboardingView

struct OnboardingView: View {
    let settings: SettingsManager

    @State private var currentStep: OnboardingStep = .welcome
    @State private var stepIndex = 0
    @State private var goingForward = true

    // Collected state
    @State private var apiKey = ""
    @State private var hasExistingKey = false
    @State private var launchAtLogin = true

    // Agent tool detection
    @State private var agentToolStatuses: [AgentToolDetector.Status] = []

    private var steps: [OnboardingStep] {
        if hasExistingKey {
            return [.welcome, .connectAgent, .done]
        } else {
            return [.welcome, .connectAgent, .apiKey, .done]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStep()
                case .connectAgent:
                    ConnectAgentStep(statuses: agentToolStatuses)
                case .apiKey:
                    APIKeyStep(apiKey: $apiKey)
                case .done:
                    DoneStep(
                        hasAPIKey: !apiKey.isEmpty,
                        pluginInstalled: agentToolStatuses.contains(where: \.pluginInstalled),
                        launchAtLogin: $launchAtLogin
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(currentStep)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: goingForward ? 1.04 : 0.96)),
                removal: .opacity.combined(with: .scale(scale: goingForward ? 0.96 : 1.04))
            ))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            StepDots(count: steps.count, currentIndex: stepIndex)
                .padding(.top, 8)

            NavBar(
                step: currentStep,
                isFirstStep: stepIndex == 0,
                isLastStep: stepIndex == steps.count - 1,
                canSkip: currentStep == .connectAgent || currentStep == .apiKey,
                onBack: goBack,
                onNext: goNext,
                onDone: handleComplete
            )
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 32)
        .frame(width: 520, height: 540)
        .focusEffectDisabled()
        .task {
            agentToolStatuses = AgentToolDetector.detect()

            let existingKey = (try? KeychainHelper.readPersistedAPIKey()) ?? settings.openAIAPIKey
            hasExistingKey = !existingKey.isEmpty
            if hasExistingKey { apiKey = existingKey }

            try? await Task.sleep(for: .milliseconds(600))
            speakDemoWithPrerecorded(resource: "onboarding-openai", ext: "mp3")
        }
        .onChange(of: currentStep) { _, newStep in
            handleStepChange(newStep)
        }
        .onChange(of: apiKey) { _, newKey in
            if !newKey.isEmpty {
                settings.openAIAPIKey = newKey
            }
        }
    }

    private func goBack() {
        stopAllAudio()
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        goingForward = false
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = steps[stepIndex]
        }
    }

    private func goNext() {
        stopAllAudio()
        guard stepIndex < steps.count - 1 else { return }
        stepIndex += 1
        goingForward = true
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = steps[stepIndex]
        }
    }

    private func stopAllAudio() {
        ackDemo()
    }

    private func handleComplete() {
        stopAllAudio()

        if !apiKey.isEmpty {
            settings.openAIAPIKey = apiKey
            settings.voiceEngine = .openai
        }
        settings.networkListenerEnabled = true
        settings.launchAtLogin = launchAtLogin
        settings.hasCompletedOnboarding = true

        Log.onboarding.info("Onboarding completed")
        NSApp.keyWindow?.close()
    }

    private func handleStepChange(_ step: OnboardingStep) {
        switch step {
        case .welcome:
            speakDemoWithPrerecorded(resource: "onboarding-openai", ext: "mp3")
        case .connectAgent, .apiKey:
            break
        case .done:
            speakDemo("VoxClaw is ready. Let's go!")
        }
    }

    private func speakDemoWithPrerecorded(resource: String, ext: String) {
        guard let url = Bundle.module.url(forResource: resource, withExtension: ext) else {
            speakDemo("Welcome to VoxClaw. Your coding agent can finally talk.")
            return
        }
        let displayText = "Hey, welcome to VoxClaw! This is what your coding agent sounds like when it talks to you. Pretty cool, right? You can choose from different voices, adjust the speed, and see every word highlighted as it's spoken."
        let engine = PrerecordedSpeechEngine(audioURL: url)
        SharedApp.coordinator.queue.enqueue(
            displayText,
            appState: SharedApp.appState,
            settings: settings,
            engineOverride: engine,
            projectId: "onboarding"
        )
    }

    private func speakDemo(_ text: String) {
        SharedApp.coordinator.queue.enqueue(
            text,
            appState: SharedApp.appState,
            settings: settings,
            projectId: "onboarding"
        )
    }

    private func ackDemo() {
        SharedApp.coordinator.queue.handleAck(projectId: "onboarding", appState: SharedApp.appState)
    }
}

// MARK: - Step Dots

private struct StepDots: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: index == currentIndex ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
            }
        }
    }
}

// MARK: - Nav Bar

private struct NavBar: View {
    let step: OnboardingStep
    let isFirstStep: Bool
    let isLastStep: Bool
    let canSkip: Bool
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
                        .accessibilityIdentifier(AccessibilityID.Onboarding.backButton)
                } else {
                    Button("Back") { onBack() }
                        .accessibilityIdentifier(AccessibilityID.Onboarding.backButton)
                }
#else
                Button("Back") { onBack() }
                    .accessibilityIdentifier(AccessibilityID.Onboarding.backButton)
#endif
            }

            Spacer()

            if isFirstStep {
                prominentActionButton(title: "Get Started", action: onNext)
                    .accessibilityIdentifier(AccessibilityID.Onboarding.getStartedButton)
            } else if step == .done {
                prominentActionButton(title: "Done", action: onDone)
                .accessibilityIdentifier(AccessibilityID.Onboarding.finishButton)
            } else {
                if canSkip {
                    Button("Skip") { onNext() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.trailing, 6)
                }
                prominentActionButton(title: "Continue", action: onNext)
                    .accessibilityIdentifier(AccessibilityID.Onboarding.continueButton)
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
    var body: some View {
        VStack(spacing: 24) {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 160, height: 160)
            }

            VStack(spacing: 8) {
                Text("Welcome to VoxClaw")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Give your coding agent a voice,\nright here on your Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Connect Agent Step

private struct ConnectAgentStep: View {
    let statuses: [AgentToolDetector.Status]
    @State private var copiedCommand: AgentToolDetector.Tool?
    @State private var expandedManual = false

    private var installedTools: [AgentToolDetector.Status] {
        statuses.filter(\.installed)
    }

    private var missingTools: [AgentToolDetector.Status] {
        statuses.filter { !$0.installed }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text("Connect Your Agent")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Install the VoxClaw plugin so your agent\nspeaks its responses aloud.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                if installedTools.isEmpty {
                    noToolsView
                } else {
                    ForEach(installedTools, id: \.tool) { status in
                        toolCard(status)
                    }
                    if !missingTools.isEmpty {
                        Text("Also available:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                        ForEach(missingTools, id: \.tool) { status in
                            missingToolRow(status)
                        }
                    }
                }
            }

            if !installedTools.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedManual.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Other integration methods")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: expandedManual ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if expandedManual {
                    manualIntegrationView
                }
            }

            Text("You can always set this up later in Settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var noToolsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("No coding agents detected on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("VoxClaw works with Claude Code and Codex.\nInstall one to get started:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                ForEach(AgentToolDetector.Tool.allCases, id: \.self) { tool in
                    Link(destination: AgentToolDetector.downloadURL(for: tool)) {
                        HStack(spacing: 6) {
                            Image(systemName: AgentToolDetector.iconName(for: tool))
                            Text("Get \(AgentToolDetector.displayName(for: tool))")
                        }
                        .font(.callout)
                    }
                }
            }

            Divider().padding(.horizontal, 20)

            manualIntegrationView
        }
    }

    private func toolCard(_ status: AgentToolDetector.Status) -> some View {
        HStack(spacing: 12) {
            Image(systemName: AgentToolDetector.iconName(for: status.tool))
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(AgentToolDetector.displayName(for: status.tool))
                        .font(.body)
                        .fontWeight(.medium)
                    if status.pluginInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Group {
                    if copiedCommand == status.tool {
                        Text("Copied — paste in Terminal with ⌘V")
                            .foregroundStyle(.green)
                    } else if status.pluginInstalled {
                        Text("VoxClaw plugin installed")
                            .foregroundStyle(.green)
                    } else {
                        Text("Detected — plugin not yet installed")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .animation(.easeInOut(duration: 0.2), value: copiedCommand)
            }

            Spacer()

            if status.pluginInstalled {
                Text("Ready")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Button {
                    let cmd = AgentToolDetector.installCommand(for: status.tool)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    copiedCommand = status.tool

                    if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                        NSWorkspace.shared.openApplication(at: terminalURL, configuration: .init())
                    }

                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        copiedCommand = nil
                    }
                } label: {
                    Text(copiedCommand == status.tool ? "Copied!" : "Install")
                        .font(.caption)
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .modifier(GlassBackgroundModifier())
    }

    private func missingToolRow(_ status: AgentToolDetector.Status) -> some View {
        HStack(spacing: 12) {
            Image(systemName: AgentToolDetector.iconName(for: status.tool))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            Text(AgentToolDetector.displayName(for: status.tool))
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Link("Download", destination: AgentToolDetector.downloadURL(for: status.tool))
                .font(.caption)
        }
        .padding(.horizontal, 12)
    }

    private var manualIntegrationView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You can also send text directly:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("curl -X POST http://localhost:4140/read \\\n  -d '{\"text\": \"Hello from your agent\"}'")
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(GlassBackgroundModifier())
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

            Text("For natural-sounding voices, add your\nOpenAI API key. Your Mac's built-in voice\nworks great too — no key needed.")
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
                        .accessibilityIdentifier(AccessibilityID.Onboarding.removeAPIKey)
                    }
                } else {
                    HStack {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(AccessibilityID.Onboarding.apiKeyField)
                        Button("Paste") {
                            if let clip = NSPasteboard.general.string(forType: .string) {
                                apiKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .accessibilityIdentifier(AccessibilityID.Onboarding.pasteAPIKey)
                    }

                    HStack(spacing: 4) {
                        Link("Get an API key",
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .accessibilityIdentifier(AccessibilityID.Onboarding.getAPIKeyLink)
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


// MARK: - Done Step

private struct DoneStep: View {
    let hasAPIKey: Bool
    let pluginInstalled: Bool
    @Binding var launchAtLogin: Bool

    @State private var appeared = false

    private var isFullyReady: Bool {
        pluginInstalled
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 72, height: 72)
                    .scaleEffect(appeared ? 1.0 : 0.5)
                    .opacity(appeared ? 1 : 0)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.green)
                    .scaleEffect(appeared ? 1.0 : 0.3)
                    .opacity(appeared ? 1 : 0)
            }

            Text("VoxClaw is Ready")
                .font(.title)
                .fontWeight(.bold)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            Text(isFullyReady
                 ? "Start a coding session and your agent\nwill speak its responses."
                 : "It's running in your menu bar.\nFinish setup anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                StatusRow(done: pluginInstalled, label: "Agent plugin connected",
                          hint: "Set up in Settings", delay: 0.3, appeared: appeared)
                StatusRow(done: hasAPIKey, label: "Voice engine configured",
                          hint: "Using Apple Built-in (free)", delay: 0.45, appeared: appeared)
                StatusRow(done: true, label: "Network listener enabled",
                          hint: nil, delay: 0.6, appeared: appeared)
            }
            .padding(14)
            .modifier(GlassBackgroundModifier())

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .font(.callout)
                .padding(.horizontal, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.7), value: appeared)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                appeared = true
            }
        }
    }
}

private struct StatusRow: View {
    let done: Bool
    let label: String
    let hint: String?
    let delay: Double
    let appeared: Bool

    @State private var visible = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? .green : .secondary)
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                    .fontWeight(done ? .medium : .regular)
                    .foregroundStyle(done ? .primary : .secondary)
                if !done, let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : -8)
        .onChange(of: appeared) { _, show in
            if show {
                withAnimation(.easeOut(duration: 0.3).delay(delay)) {
                    visible = true
                }
            }
        }
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

#endif
