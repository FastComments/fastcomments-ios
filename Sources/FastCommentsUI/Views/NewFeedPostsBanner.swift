import SwiftUI

/// Banner showing "Show N New Posts" that appears at the top of the feed when live posts arrive.
struct NewFeedPostsBanner: View {
    let count: Int
    var onTap: (() -> Void)?

    @Environment(\.fastCommentsTheme) private var theme

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 14))
                Text(String(localized: "show_new_posts_\(count)", bundle: .module))
                .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(theme.resolveLoadMoreButtonTextColor())
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(theme.resolveLoadMoreButtonTextColor().opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius.inner))
            .padding(.horizontal, theme.feedContentPadding)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-feed-posts-banner")
    }
}
