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
                                if appState.words[index] == ReadingSession.paragraphSentinel {
                                    Color.clear
                                        .frame(width: 0, height: 0)
                                        .paragraphBreak()
                                        .id(index)
                                } else {
                                    TeleprompterWordView(
                                        word: appState.words[index],
                                        isHighlighted: index == appState.currentWordIndex,
                                        isPast: index < appState.currentWordIndex,
                                        isPaused: appState.isPaused,
                                        appearance: appearance
                                    )
                                    .id(index)
                                }
                            }
                        }
                        .padding(.horizontal, appearance.horizontalPadding)
                        .padding(.vertical, appearance.verticalPadding + 60)
                    }
                    .clipped()
                    .onChange(of: appState.currentWordIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: UnitPoint(x: 0, y: 0.5))
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

            // Project indicators
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
                .padding(.top, 56)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
