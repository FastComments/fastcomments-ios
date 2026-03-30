import SwiftUI

/// Button showing "Show N new comments/replies" with polished styling.
public struct NewCommentsButton: View {
    let button: RenderableButton
    var onTap: (() -> Void)?

    @Environment(\.fastCommentsTheme) private var theme

    public var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                Text(buttonText)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(theme.resolveLoadMoreButtonTextColor())
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(theme.resolveLoadMoreButtonTextColor().opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var buttonText: String {
        switch button.buttonType {
        case .newRootComments:
            return String(
                format: NSLocalizedString("show_new_comments_%lld", bundle: .module, comment: ""),
                button.commentCount
            )
        case .newChildComments:
            return String(
                format: NSLocalizedString("show_new_replies_%lld", bundle: .module, comment: ""),
                button.commentCount
            )
        }
    }
}
