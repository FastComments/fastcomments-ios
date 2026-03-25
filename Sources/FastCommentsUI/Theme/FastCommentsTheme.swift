import SwiftUI

/// Customizable color theme for FastComments UI components.
/// All colors are optional — unset colors fall back to sensible defaults.
public struct FastCommentsTheme: Sendable {
    // Primary colors
    public var primaryColor: Color?
    public var primaryLightColor: Color?
    public var primaryDarkColor: Color?

    // Action button colors
    public var actionButtonColor: Color?
    public var replyButtonColor: Color?
    public var toggleRepliesButtonColor: Color?
    public var loadMoreButtonTextColor: Color?

    // Link colors
    public var linkColor: Color?
    public var linkColorPressed: Color?

    // Vote colors
    public var voteCountColor: Color?
    public var voteCountZeroColor: Color?
    public var voteDividerColor: Color?

    // Dialog/sheet colors
    public var dialogHeaderBackgroundColor: Color?
    public var dialogHeaderTextColor: Color?

    // Other
    public var onlineIndicatorColor: Color?

    public init() {}

    /// Set all action-related colors to a single primary color.
    public static func allPrimary(_ color: Color) -> FastCommentsTheme {
        var theme = FastCommentsTheme()
        theme.primaryColor = color
        theme.actionButtonColor = color
        theme.replyButtonColor = color
        theme.toggleRepliesButtonColor = color
        theme.loadMoreButtonTextColor = color
        return theme
    }

    // MARK: - Resolve methods (with defaults)

    public func resolveActionButtonColor() -> Color {
        actionButtonColor ?? primaryColor ?? .accentColor
    }

    public func resolveReplyButtonColor() -> Color {
        replyButtonColor ?? primaryColor ?? .accentColor
    }

    public func resolveToggleRepliesButtonColor() -> Color {
        toggleRepliesButtonColor ?? primaryColor ?? .accentColor
    }

    public func resolveLoadMoreButtonTextColor() -> Color {
        loadMoreButtonTextColor ?? primaryColor ?? .accentColor
    }

    public func resolveLinkColor() -> Color {
        linkColor ?? primaryColor ?? .accentColor
    }

    public func resolveLinkColorPressed() -> Color {
        linkColorPressed ?? primaryLightColor ?? resolveLinkColor().opacity(0.7)
    }

    public func resolveVoteCountColor() -> Color {
        voteCountColor ?? .primary
    }

    public func resolveVoteCountZeroColor() -> Color {
        voteCountZeroColor ?? .secondary
    }

    public func resolveVoteDividerColor() -> Color {
        #if os(iOS)
        voteDividerColor ?? Color(uiColor: .separator)
        #else
        voteDividerColor ?? Color(nsColor: .separatorColor)
        #endif
    }

    public func resolveDialogHeaderBackgroundColor() -> Color {
        dialogHeaderBackgroundColor ?? primaryColor ?? .accentColor
    }

    public func resolveDialogHeaderTextColor() -> Color {
        dialogHeaderTextColor ?? .white
    }

    public func resolveOnlineIndicatorColor() -> Color {
        onlineIndicatorColor ?? .green
    }

    public func resolvePrimaryColor() -> Color {
        primaryColor ?? .accentColor
    }

    public func resolvePrimaryLightColor() -> Color {
        primaryLightColor ?? resolvePrimaryColor().opacity(0.7)
    }

    public func resolvePrimaryDarkColor() -> Color {
        primaryDarkColor ?? resolvePrimaryColor()
    }
}
