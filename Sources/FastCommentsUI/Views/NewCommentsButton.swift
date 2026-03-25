import SwiftUI

/// Button showing "Show N new comments/replies".
public struct NewCommentsButton: View {
    let button: RenderableButton
    var onTap: (() -> Void)?

    @Environment(\.fastCommentsTheme) private var theme

    public var body: some View {
        Button {
            onTap?()
        } label: {
            HStack {
                Image(systemName: "arrow.down.circle")
                Text(buttonText)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(theme.resolveLoadMoreButtonTextColor())
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
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
