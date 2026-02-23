import SwiftUI

public struct FeedbackBadge: View {
    public let text: String?

    public init(text: String?) {
        self.text = text
    }

    public var body: some View {
        if let text {
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .applyFeedbackBadgeGlass()
                .accessibilityIdentifier(AccessibilityID.Overlay.feedbackBadge)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private extension View {
    @ViewBuilder
    func applyFeedbackBadgeGlass() -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, iOS 26, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
#else
        self.background(.ultraThinMaterial, in: Capsule())
#endif
    }
}
