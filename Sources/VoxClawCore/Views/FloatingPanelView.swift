import SwiftUI

struct FloatingPanelView: View {
    let appState: AppState
    let settings: SettingsManager
    var onTogglePause: () -> Void = {}
    var onOpenSettings: (() -> Void)?

    @State private var isHovering = false

    private var appearance: OverlayAppearance { settings.overlayAppearance }

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
                                appearance: appearance,
                                timingSource: appState.timingSource
                            )
                            .id(index)
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

            // Feedback badge overlay (pause/resume/skip indicators)
            VStack {
                Spacer()
                FeedbackBadge(text: appState.feedbackText)
                    .animation(.easeInOut(duration: 0.2), value: appState.feedbackText)
                    .padding(.bottom, 12)
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

            if isHovering {
                overlayControls
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .accessibilityIdentifier(AccessibilityID.Overlay.panel)
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
    let appearance: OverlayAppearance
    var timingSource: TimingSource = .cadence

    var body: some View {
        Text(word)
            .font(.custom(appearance.fontFamily, size: appearance.fontSize).weight(appearance.fontWeightValue))
            .foregroundStyle(textColor)
            .padding(.horizontal, isHighlighted ? 4 : 0)
            .padding(.vertical, isHighlighted ? 2 : 0)
            .background(
                Group {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(debugHighlightColor)
                    }
                }
            )
    }

    /// Debug: different highlight colors per timing source.
    /// Red = cadence heuristic, orange = aligner partial, green = proportional, blue = final aligned.
    private var debugHighlightColor: Color {
        switch timingSource {
        case .cadence: return .red.opacity(0.7)
        case .aligner: return .orange.opacity(0.7)
        case .proportional: return .green.opacity(0.7)
        case .aligned: return .blue.opacity(0.7)
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
