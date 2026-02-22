import SwiftUI
import VoxClawCore

struct TeleprompterView: View {
    let appState: AppState
    let settings: SettingsManager
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}

    @State private var currentPresetIndex: Int = 0
    @State private var presetNameToast: String?

    private var appearance: OverlayAppearance { settings.overlayAppearance }

    var body: some View {
        ZStack {
            appearance.backgroundColor.color
                .ignoresSafeArea()

            if appState.sessionState == .loading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        FlowLayout(hSpacing: appearance.wordSpacing, vSpacing: appearance.effectiveLineSpacing) {
                            ForEach(appState.words.indices, id: \.self) { index in
                                TeleprompterWordView(
                                    word: appState.words[index],
                                    isHighlighted: index == appState.currentWordIndex,
                                    isPast: index < appState.currentWordIndex,
                                    appearance: appearance
                                )
                                .id(index)
                            }
                        }
                        .padding(.horizontal, appearance.horizontalPadding)
                        .padding(.vertical, appearance.verticalPadding + 60)
                    }
                    .onChange(of: appState.currentWordIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            // Preset name toast
            if let toast = presetNameToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                        .padding(.bottom, 70)
                }
                .allowsHitTesting(false)
            }

            // Controls overlay
            VStack {
                HStack {
                    Button(action: onStop) {
                        Image(systemName: "xmark")
                            .font(.system(.body, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    Button(action: onTogglePause) {
                        Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(.body, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                FeedbackBadge(text: appState.feedbackText)
                    .animation(.easeInOut(duration: 0.2), value: appState.feedbackText)
                    .padding(.bottom, 20)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let presets = OverlayPreset.all
                    guard presets.count > 1 else { return }
                    let threshold: CGFloat = 60
                    if value.translation.width > threshold {
                        // Swipe right → previous preset
                        currentPresetIndex = (currentPresetIndex - 1 + presets.count) % presets.count
                    } else if value.translation.width < -threshold {
                        // Swipe left → next preset
                        currentPresetIndex = (currentPresetIndex + 1) % presets.count
                    } else {
                        return
                    }
                    let preset = presets[currentPresetIndex]
                    withAnimation(.easeInOut(duration: 0.3)) {
                        settings.overlayAppearance = preset.appearance
                        presetNameToast = preset.name
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { presetNameToast = nil }
                    }
                }
        )
        .onAppear {
            let current = settings.overlayAppearance
            if let index = OverlayPreset.all.firstIndex(where: { $0.appearance == current }) {
                currentPresetIndex = index
            }
        }
        .statusBarHidden()
    }
}

private struct TeleprompterWordView: View {
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
