import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Shapes and layout shared by the poll card and the poll builder.
enum PollStyle {
    static let optionRadius: CGFloat = 11
    static let markRadius: CGFloat = 6
    static let markSize: CGFloat = 18

    /// Rounded on every corner but the top-leading one, the web chips' "border-start-start-radius: 0".
    static func shape(radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: radius
        )
    }

    /// Reads a message out through VoiceOver, for one that appears without the user moving to it.
    static func announce(_ message: String) {
        #if canImport(UIKit)
            UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}

/// Lays its children out left to right, wrapping to a new line when one would not fit. The poll footers use it so a long
/// translation or a large text size wraps instead of being squeezed and clipped.
struct PollFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 12
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placements = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let usedWidth = placements.map { $0.origin.x + $0.size.width }.max() ?? 0
        let usedHeight = placements.map { $0.origin.y + $0.size.height }.max() ?? 0
        let isWidthFinite = proposal.width?.isFinite == true
        return CGSize(width: isWidthFinite ? proposal.width ?? usedWidth : usedWidth, height: usedHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placements = arrange(subviews: subviews, width: bounds.width)
        for (subview, placement) in zip(subviews, placements) {
            subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [CGRect] {
        var placements: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var lineStart = 0

        func finishLine() {
            // Vertically center each item within its line, so a pill and a text link share a midline.
            for index in lineStart..<placements.count {
                placements[index].origin.y += (lineHeight - placements[index].height) / 2
            }
            lineStart = placements.count
        }

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                finishLine()
                y += lineHeight + verticalSpacing
                x = 0
                lineHeight = 0
            }
            placements.append(CGRect(x: x, y: y, width: min(size.width, width), height: size.height))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        finishLine()
        return placements
    }
}
