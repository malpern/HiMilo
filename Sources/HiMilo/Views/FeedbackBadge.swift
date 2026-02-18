import SwiftUI

struct FeedbackBadge: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                )
                .transition(.scale.combined(with: .opacity))
        }
    }
}
