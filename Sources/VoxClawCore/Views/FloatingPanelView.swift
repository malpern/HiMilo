import SwiftUI

struct FloatingPanelView: View {
    let appState: AppState
    let settings: SettingsManager
    var onTogglePause: () -> Void = {}
    var onOpenSettings: (() -> Void)?

    private var appearance: OverlayAppearance { settings.overlayAppearance }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(appearance.backgroundColor.color)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(hSpacing: appearance.wordSpacing, vSpacing: appearance.lineSpacing) {
                        ForEach(appState.words.indices, id: \.self) { index in
                            WordView(
                                word: appState.words[index],
                                isHighlighted: index == appState.currentWordIndex,
                                isPast: index < appState.currentWordIndex,
                                appearance: appearance
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

            overlayControls
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
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .help("Overlay Settings")
                    .accessibilityIdentifier(AccessibilityID.Overlay.settingsButton)
                }
                Button(action: onTogglePause) {
                    Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .help(appState.isPaused ? "Resume" : "Pause")
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
                            .fill(appearance.highlightColor.color)
                    }
                }
            )
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
