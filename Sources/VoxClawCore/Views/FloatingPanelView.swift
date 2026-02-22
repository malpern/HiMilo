import SwiftUI

struct FloatingPanelView: View {
    let appState: AppState
    let settings: SettingsManager
    var onTogglePause: () -> Void = {}
    var onOpenSettings: (() -> Void)?

    @State private var isHovering = false
    @State private var showPauseButton = false
    @State private var pauseButtonPulse = false
    @State private var pauseButtonHideTask: Task<Void, Never>?

    private var appearance: OverlayAppearance { settings.overlayAppearance }

    private var readingProgress: Double {
        guard appState.words.count > 1 else { return 0 }
        return Double(appState.currentWordIndex) / Double(appState.words.count - 1)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(appearance.backgroundColor.color)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(hSpacing: appearance.wordSpacing, vSpacing: appearance.effectiveLineSpacing) {
                        ForEach(appState.words.indices, id: \.self) { index in
                            WordView(
                                word: appState.words[index],
                                isHighlighted: index == appState.currentWordIndex,
                                isPast: index < appState.currentWordIndex,
                                isPaused: appState.isPaused,
                                appearance: appearance
                            )
                            .id(index)
                        }
                        if !appState.words.isEmpty {
                            Text("🦀")
                                .font(.custom(appearance.fontFamily, size: appearance.fontSize))
                                .opacity(appearance.futureWordOpacity)
                                .id("crab")
                        }
                    }
                    .padding(.horizontal, appearance.horizontalPadding)
                    .padding(.vertical, appearance.verticalPadding)
                }
                .onChange(of: appState.currentWordIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            // Speed indicator (bottom-right, fades in/out)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FeedbackBadge(text: appState.speedIndicatorText)
                        .animation(.easeInOut(duration: 0.2), value: appState.speedIndicatorText)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
            }

            // Timing source indicator — small dot visible during early heuristic, fades when better algo arrives
            if appState.timingSource == .cadence || appState.timingSource == .aligner {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Circle()
                            .fill(.white.opacity(0.25))
                            .frame(width: 5, height: 5)
                            .padding(.trailing, 10)
                            .padding(.bottom, 10)
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.5), value: appState.timingSource)
            }

            // Subtle progress bar at the very bottom, respecting corner radius
            VStack(spacing: 0) {
                Spacer()
                ProgressBarView(
                    progress: readingProgress,
                    cornerRadius: appearance.cornerRadius,
                    color: appearance.highlightColor.color
                )
            }

            if isHovering || showPauseButton {
                overlayControls
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onChange(of: appState.isPaused) { _, _ in
            flashPauseButton()
        }
        .accessibilityIdentifier(AccessibilityID.Overlay.panel)
    }

    private func flashPauseButton() {
        // Show the button and pulse it to draw attention
        withAnimation(.easeInOut(duration: 0.2)) {
            showPauseButton = true
        }
        withAnimation(.spring(duration: 0.25, bounce: 0.4)) {
            pauseButtonPulse = true
        }
        // Settle back to normal size
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) {
                pauseButtonPulse = false
            }
        }
        // Hide after a few seconds
        pauseButtonHideTask?.cancel()
        pauseButtonHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !isHovering else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                showPauseButton = false
            }
        }
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                Spacer()
                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(.callout, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("Overlay Settings")
                    #endif
                    .accessibilityIdentifier(AccessibilityID.Overlay.settingsButton)
                }
                Button(action: onTogglePause) {
                    Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(.callout, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .scaleEffect(pauseButtonPulse ? 1.3 : 1.0)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help(appState.isPaused ? "Resume" : "Pause")
                #endif
                .accessibilityIdentifier(AccessibilityID.Overlay.pauseButton)
            }
            .padding(.trailing, 12)
            .padding(.top, 10)
            Spacer()
        }
    }
}

private struct WordView: View {
    let word: String
    let isHighlighted: Bool
    let isPast: Bool
    var isPaused: Bool = false
    let appearance: OverlayAppearance

    @State private var glowRadius: CGFloat = 3

    private var highlightColor: Color { appearance.highlightColor.color }

    var body: some View {
        Text(word)
            .font(.custom(appearance.fontFamily, size: appearance.fontSize).weight(appearance.fontWeightValue))
            .foregroundStyle(textColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(highlightColor)
                    .opacity(isHighlighted ? 1 : 0)
                    .shadow(color: highlightColor.opacity(isHighlighted ? 0.4 : 0), radius: glowRadius)
            )
            .animation(.easeInOut(duration: 0.12), value: isHighlighted)
            .onChange(of: isPaused) { _, paused in
                if paused && isHighlighted {
                    startBreathe()
                } else {
                    stopBreathe()
                }
            }
            .onChange(of: isHighlighted) { _, highlighted in
                if highlighted && isPaused {
                    startBreathe()
                } else if !highlighted {
                    stopBreathe()
                }
            }
    }

    private func startBreathe() {
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            glowRadius = 8
        }
    }

    private func stopBreathe() {
        withAnimation(.easeInOut(duration: 0.2)) {
            glowRadius = 3
        }
    }

    private var textColor: Color {
        if isHighlighted {
            return appearance.textColor.color
        } else if isPast {
            return appearance.textColor.color.opacity(appearance.pastWordOpacity)
        } else {
            return appearance.textColor.color.opacity(appearance.futureWordOpacity)
        }
    }
}

/// A 1.5pt progress line that hugs the bottom of the overlay, clipped to the panel's corner radius.
private struct ProgressBarView: View {
    let progress: Double
    let cornerRadius: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * min(max(progress, 0), 1)
            Rectangle()
                .fill(color.opacity(0.5))
                .frame(width: width, height: 1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 1.5)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius))
        .animation(.linear(duration: 0.15), value: progress)
    }
}
