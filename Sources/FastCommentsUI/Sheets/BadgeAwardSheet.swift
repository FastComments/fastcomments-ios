import SwiftUI
import FastCommentsSwift

/// Sheet displaying a badge award to the user.
/// Mirrors BadgeAwardDialog.java from Android.
public struct BadgeAwardSheet: View {
    let badges: [CommentUserBadgeInfo]

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text(NSLocalizedString("badge_awarded", bundle: .module, comment: ""))
                .font(.title2)
                .fontWeight(.bold)

            ForEach(badges) { badge in
                VStack(spacing: 8) {
                    BadgeView(badge: badge)
                    Text(badge.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button(NSLocalizedString("ok", bundle: .module, comment: "")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
