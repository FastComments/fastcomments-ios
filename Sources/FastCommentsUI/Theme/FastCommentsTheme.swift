import SwiftUI

/// Customizable theme for FastComments UI components.
/// All properties are optional — unset values fall back to sensible defaults.
///
/// ## Quick Start
/// ```swift
/// // Use a preset
/// let theme = FastCommentsTheme.modern
///
/// // Or build your own
/// var theme = FastCommentsTheme()
/// theme.primaryColor = .blue
/// theme.cornerRadius = .large
/// theme.commentStyle = .card
/// ```
public struct FastCommentsTheme: Sendable {

    // MARK: - Colors

    /// Primary brand color used throughout the UI.
    public var primaryColor: Color?
    public var primaryLightColor: Color?
    public var primaryDarkColor: Color?

    /// Background color for comment cards/bubbles.
    public var commentBackgroundColor: Color?
    /// Background color for the overall comments container.
    public var containerBackgroundColor: Color?

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
    public var voteActiveColor: Color?

    // Dialog/sheet colors
    public var dialogHeaderBackgroundColor: Color?
    public var dialogHeaderTextColor: Color?

    // Input bar
    public var inputBarBackgroundColor: Color?
    public var inputBarBorderColor: Color?

    // Other
    public var onlineIndicatorColor: Color?
    public var separatorColor: Color?
    public var badgeBackgroundColor: Color?

    // MARK: - Typography

    /// Font for commenter names.
    public var commenterNameFont: Font?
    /// Font for comment body text.
    public var bodyFont: Font?
    /// Font for timestamps and captions.
    public var captionFont: Font?
    /// Font for action buttons (reply, vote, etc.).
    public var actionFont: Font?

    // MARK: - Spacing & Layout

    /// Corner radius style for cards and containers.
    public var cornerRadius: CornerRadiusStyle = .medium

    /// How comments are visually presented.
    public var commentStyle: CommentDisplayStyle = .flat

    /// Spacing between comment rows.
    public var commentSpacing: CGFloat = 0

    /// Indentation per nesting level (in points).
    public var nestingIndent: CGFloat = 20

    /// Avatar size for root-level comments.
    public var avatarSize: CGFloat = 36

    /// Avatar size for nested replies.
    public var replyAvatarSize: CGFloat = 28

    /// Horizontal content padding for feed posts (header, text, media, actions, dividers).
    public var feedContentPadding: CGFloat = 14

    /// Avatar size for feed post headers.
    public var feedAvatarSize: CGFloat = 42

    /// Height for feed post media (single image and carousel).
    public var feedMediaHeight: CGFloat = 280

    /// Size of action bar icons (comment, like, share) in feed posts.
    public var feedActionIconSize: CGFloat = 15

    // MARK: - Visual Effects

    /// Whether to show subtle shadows on cards.
    public var showShadows: Bool = false

    /// Whether to show the threading line for nested comments.
    public var showThreadLine: Bool = true

    /// Thread line color.
    public var threadLineColor: Color?

    /// Whether to animate vote count changes.
    public var animateVotes: Bool = true

    // MARK: - Enums

    public enum CornerRadiusStyle: Sendable {
        case none, small, medium, large

        public var value: CGFloat {
            switch self {
            case .none: return 0
            case .small: return 6
            case .medium: return 12
            case .large: return 16
            }
        }

        public var inner: CGFloat {
            switch self {
            case .none: return 0
            case .small: return 4
            case .medium: return 8
            case .large: return 12
            }
        }
    }

    public enum CommentDisplayStyle: Sendable {
        /// Flat list with dividers (default).
        case flat
        /// Each comment in a rounded card with subtle shadow.
        case card
        /// Chat bubble style, ideal for live chat.
        case bubble
    }

    public init() {}

    // MARK: - Presets

    /// Default theme with system colors.
    public static var `default`: FastCommentsTheme { FastCommentsTheme() }

    /// Modern theme with cards, shadows, and rounded corners.
    public static var modern: FastCommentsTheme {
        var theme = FastCommentsTheme()
        theme.commentStyle = .card
        theme.showShadows = true
        theme.cornerRadius = .large
        theme.showThreadLine = true
        theme.animateVotes = true
        return theme
    }

    /// Minimal flat theme with subtle styling.
    public static var minimal: FastCommentsTheme {
        var theme = FastCommentsTheme()
        theme.commentStyle = .flat
        theme.showShadows = false
        theme.cornerRadius = .small
        theme.showThreadLine = false
        return theme
    }

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

    public func resolveVoteActiveColor() -> Color {
        voteActiveColor ?? resolveActionButtonColor()
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

    public func resolveCommentBackgroundColor() -> Color {
        #if os(iOS)
        commentBackgroundColor ?? Color(uiColor: .secondarySystemGroupedBackground)
        #else
        commentBackgroundColor ?? Color(nsColor: .controlBackgroundColor)
        #endif
    }

    public func resolveContainerBackgroundColor() -> Color {
        #if os(iOS)
        containerBackgroundColor ?? Color(uiColor: .systemGroupedBackground)
        #else
        containerBackgroundColor ?? Color(nsColor: .windowBackgroundColor)
        #endif
    }

    public func resolveInputBarBackgroundColor() -> Color {
        #if os(iOS)
        inputBarBackgroundColor ?? Color(uiColor: .systemBackground)
        #else
        inputBarBackgroundColor ?? Color(nsColor: .windowBackgroundColor)
        #endif
    }

    public func resolveInputBarBorderColor() -> Color {
        #if os(iOS)
        inputBarBorderColor ?? Color(uiColor: .separator)
        #else
        inputBarBorderColor ?? Color(nsColor: .separatorColor)
        #endif
    }

    public func resolveSeparatorColor() -> Color {
        #if os(iOS)
        separatorColor ?? Color(uiColor: .separator)
        #else
        separatorColor ?? Color(nsColor: .separatorColor)
        #endif
    }

    public func resolveThreadLineColor() -> Color {
        threadLineColor ?? resolvePrimaryColor().opacity(0.15)
    }

    public func resolveCommenterNameFont() -> Font {
        commenterNameFont ?? .subheadline.weight(.semibold)
    }

    public func resolveBodyFont() -> Font {
        bodyFont ?? .subheadline
    }

    public func resolveCaptionFont() -> Font {
        captionFont ?? .caption2
    }

    public func resolveActionFont() -> Font {
        actionFont ?? .caption.weight(.medium)
    }
}
