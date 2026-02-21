import SwiftUI

struct FloatingPanelView: View {
    let appState: AppState
    var onTogglePause: () -> Void = {}

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.85))

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(spacing: 6) {
                        ForEach(appState.words.indices, id: \.self) { index in
                            WordView(
                                word: appState.words[index],
                                isHighlighted: index == appState.currentWordIndex,
                                isPast: index < appState.currentWordIndex
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
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

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onTogglePause) {
                        Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(appState.isPaused ? "Resume" : "Pause")
                }
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }
        }
    }
}

private struct WordView: View {
    let word: String
    let isHighlighted: Bool
    let isPast: Bool

    var body: some View {
        Text(word)
            .font(.custom("Helvetica Neue", size: 28).weight(.medium))
            .foregroundStyle(textColor)
            .padding(.horizontal, isHighlighted ? 4 : 0)
            .padding(.vertical, isHighlighted ? 2 : 0)
            .background(
                Group {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.yellow.opacity(0.35))
                    }
                }
            )
    }

    private var textColor: Color {
        if isHighlighted {
            return .white
        } else if isPast {
            return .white.opacity(0.5)
        } else {
            return .white.opacity(0.9)
        }
    }
}
