import SwiftUI
import FastCommentsSwift

/// Displays a user badge (image or text label) with polished styling.
public struct BadgeView: View {
    let badge: CommentUserBadgeInfo

    public var body: some View {
        if let displaySrc = badge.displaySrc, let url = URL(string: displaySrc) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                badgeLabel
            }
            .frame(height: 16)
        } else {
            badgeLabel
        }
    }

    @ViewBuilder
    private var badgeLabel: some View {
        if let label = badge.displayLabel {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeBackgroundColor)
                .foregroundStyle(badgeTextColor)
                .clipShape(Capsule())
        }
    }

    private var badgeBackgroundColor: Color {
        if let hex = badge.backgroundColor {
            return Color(hex: hex) ?? .gray.opacity(0.15)
        }
        return .gray.opacity(0.15)
    }

    private var badgeTextColor: Color {
        if let hex = badge.textColor {
            return Color(hex: hex) ?? .primary
        }
        return .primary
    }
}

// MARK: - Color hex init

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        switch length {
        case 6:
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8:
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }
}
