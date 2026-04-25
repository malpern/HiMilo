import SwiftUI

struct FloatingPanelView: View {
    let appState: AppState
    let settings: SettingsManager
    var onTogglePause: () -> Void = {}
    var onOpenSettings: (() -> Void)?
    var onStop: () -> Void = {}

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
                            if appState.words[index] == ReadingSession.paragraphSentinel {
                                Color.clear
                                    .frame(width: 0, height: 0)
                                    .paragraphBreak()
                                    .id(index)
                            } else {
                                WordView(
                                    word: appState.words[index],
                                    isHighlighted: index == appState.currentWordIndex,
                                    isPast: index < appState.currentWordIndex,
                                    isPaused: appState.isPaused,
                                    appearance: appearance
                                )
                                .id(index)
                            }
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
                    .padding(.top, appState.projectIndicators.isEmpty ? 0 : 16)
                }
                .clipped()
                .onChange(of: appState.currentWordIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: UnitPoint(x: 0, y: 0.5))
                    }
                }
            }
            .padding(.horizontal, 4)

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

            // Silent-mode indicator — appears top-left when speech is being shown without audio
            // because a defer-list app (Zoom, Claude desktop, etc.) is busy.
            if appState.silentMode {
                VStack {
                    HStack {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.leading, 12)
                            .padding(.top, 10)
                            .help("Silent: another app is using audio")
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: appState.silentMode)
            }

            // Project indicators — top-left, subtle. Current + upcoming
            // projects from the speech queue, each with a colored dot.
            if !appState.projectIndicators.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(appState.projectIndicators.enumerated()), id: \.element.id) { idx, indicator in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(indicator.color.opacity(0.8))
                                .frame(width: 6, height: 6)
                            Text(indicator.name)
                                .font(.system(size: 11, weight: idx == 0 ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(idx == 0 ? 0.70 : 0.35))
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: appState.projectIndicators)
                .padding(.leading, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                            .applyOverlayControlGlass()
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
                        .applyOverlayControlGlass()
                        .scaleEffect(pauseButtonPulse ? 1.3 : 1.0)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help(appState.isPaused ? "Resume" : "Pause")
                #endif
                .accessibilityIdentifier(AccessibilityID.Overlay.pauseButton)
                Button(action: onStop) {
                    Image(systemName: "xmark")
                        .font(.system(.callout, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .applyOverlayControlGlass()
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help("Stop")
                #endif
                .accessibilityIdentifier(AccessibilityID.Overlay.stopButton)
            }
            .padding(.trailing, 12)
            .padding(.top, 10)
            Spacer()
        }
    }
}

private extension View {
    @ViewBuilder
    func applyOverlayControlGlass() -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
#else
        self.background(.ultraThinMaterial, in: Circle())
#endif
    }
}

private struct WordView: View {
    let word: String
    let isHighlighted: Bool
    let isPast: Bool
    var isPaused: Bool = false
    let appearance: OverlayAppearance

    private static let codeMarker = "\u{200B}"

    private var isCode: Bool { word.hasPrefix(Self.codeMarker) }
    private var displayWord: String { isCode ? String(word.dropFirst()) : word }

    @State private var glowRadius: CGFloat = 3

    private var highlightColor: Color { appearance.highlightColor.color }

    var body: some View {
        Text(displayWord)
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
        let base = isCode ? appearance.codeWordColor.color : appearance.textColor.color
        if isHighlighted {
            return base
        } else if isPast {
            return base.opacity(appearance.pastWordOpacity)
        } else {
            return base.opacity(appearance.futureWordOpacity)
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
