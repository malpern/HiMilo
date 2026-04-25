import SwiftUI

struct ParagraphBreakKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    func paragraphBreak() -> some View {
        layoutValue(key: ParagraphBreakKey.self, value: true)
    }
}

public struct FlowLayout: Layout {
    public var hSpacing: CGFloat
    public var vSpacing: CGFloat

    public init(hSpacing: CGFloat = 6, vSpacing: CGFloat = 6) {
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            if subview[ParagraphBreakKey.self] {
                currentX = 0
                currentY += lineHeight + vSpacing * 2
                lineHeight = 0
                positions.append(CGPoint(x: 0, y: currentY))
                continue
            }

            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + vSpacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + hSpacing
            maxX = max(maxX, currentX)
        }

        return ArrangeResult(
            size: CGSize(width: min(maxX, maxWidth), height: currentY + lineHeight),
            positions: positions
        )
    }
}
