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

    // Poll colors. Unset, the accent follows `primaryColor` and the rest match the web widget's poll card.
    /// Selected option border and check, chosen duration, and "Your vote is in".
    public var pollAccentColor: Color?
    /// Check mark and text drawn on the accent color.
    public var pollAccentTextColor: Color?
    /// Option chip background.
    public var pollOptionBackgroundColor: Color?
    /// Option chip background while pressed.
    public var pollOptionPressedBackgroundColor: Color?
    /// Result bar for options you did not pick.
    public var pollBarColor: Color?
    /// Result bar for the option you picked.
    public var pollSelectedBarColor: Color?
    /// Checkbox mark and outlined pills.
    public var pollBorderColor: Color?
    /// Errors and "Remove poll".
    public var pollDangerColor: Color?

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

    public func resolvePollAccentColor() -> Color {
        pollAccentColor ?? primaryColor ?? Self.adaptiveColor(light: 0x333333, dark: 0xFFFFFF)
    }

    public func resolvePollAccentTextColor() -> Color {
        if let pollAccentTextColor { return pollAccentTextColor }
        if let accent = pollAccentColor ?? primaryColor { return Self.readableTextColor(on: accent) }
        return Self.adaptiveColor(light: 0xFFFFFF, dark: 0x181A1B)
    }

    public func resolvePollOptionBackgroundColor() -> Color {
        pollOptionBackgroundColor ?? Self.adaptiveColor(light: 0xF6F7F8, dark: 0x181A1B)
    }

    public func resolvePollOptionPressedBackgroundColor() -> Color {
        pollOptionPressedBackgroundColor ?? Self.adaptiveColor(light: 0xECECEC, dark: 0x2A2C2D)
    }

    public func resolvePollBarColor() -> Color {
        pollBarColor ?? Self.adaptiveColor(light: 0xE5E5E5, dark: 0x353535)
    }

    public func resolvePollSelectedBarColor() -> Color {
        if let pollSelectedBarColor { return pollSelectedBarColor }
        if let accent = pollAccentColor ?? primaryColor { return accent.opacity(0.22) }
        return Self.adaptiveColor(light: 0xD9D9D9, dark: 0x4A4C4D)
    }

    public func resolvePollBorderColor() -> Color {
        pollBorderColor ?? Self.adaptiveColor(light: 0xBFBFBF, dark: 0x424242)
    }

    public func resolvePollDangerColor() -> Color {
        pollDangerColor ?? Self.adaptiveColor(light: 0xC44A3F, dark: 0xE0766C)
    }

    /// Black or white, whichever reads better on a color, so a light brand color doesn't get a white check mark.
    private static func readableTextColor(on background: Color) -> Color {
        #if os(iOS)
            let base = UIColor(background)
            return Color(
                uiColor: UIColor { traits in
                    var red: CGFloat = 0
                    var green: CGFloat = 0
                    var blue: CGFloat = 0
                    base.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: nil)
                    // WCAG relative luminance. Black has the better contrast above about 0.179.
                    let linear = [red, green, blue].map { channel -> CGFloat in
                        let clamped = min(max(channel, 0), 1)
                        return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
                    }
                    let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
                    return luminance > 0.179 ? .black : .white
                })
        #else
            return .white
        #endif
    }

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #else
            Color(
                nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(hex: dark) : NSColor(hex: light)
                })
        #endif
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

#if os(iOS)
    private extension UIColor {
        convenience init(hex: UInt32) {
            self.init(
                red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
#else
    private extension NSColor {
        convenience init(hex: UInt32) {
            self.init(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
#endif
