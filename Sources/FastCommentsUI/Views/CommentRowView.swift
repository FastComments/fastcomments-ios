import SwiftUI
import FastCommentsSwift

/// Renders a single comment row with avatar, content, votes, reply controls, and threading.
public struct CommentRowView: View {
    @ObservedObject var comment: RenderableComment
    let sdk: FastCommentsSDK
    let nestingLevel: Int
    var voteStyle: VoteStyle = ._0

    var onReply: ((RenderableComment) -> Void)?
    var onToggleReplies: ((RenderableComment) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?
    var onEdit: ((RenderableComment) -> Void)?
    var onDelete: ((RenderableComment) -> Void)?
    var onFlag: ((RenderableComment) -> Void)?
    var onPin: ((RenderableComment) -> Void)?
    var onLock: ((RenderableComment) -> Void)?
    var onBlock: ((RenderableComment) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var showMenu = false

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Thread line for nested comments
            if nestingLevel > 0 && theme.showThreadLine {
                threadLine
            }

            VStack(alignment: .leading, spacing: 8) {
                // Header: avatar, name, badges, date, menu
                headerRow

                // Comment content
                contentView

                // Action row: votes, reply, toggle replies
                actionRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .modifier(CommentStyleModifier(theme: theme, nestingLevel: nestingLevel))
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, theme.commentStyle == .card ? 12 : 0)
        .padding(.vertical, theme.commentStyle == .card ? 4 : 0)
    }

    // MARK: - Thread Line

    private var threadLine: some View {
        Rectangle()
            .fill(theme.resolveThreadLineColor())
            .frame(width: 2)
            .padding(.vertical, 4)
            .padding(.leading, 4)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onUserClick?(.comment(comment.comment), UserInfo.from(comment.comment), .avatar)
            } label: {
                AvatarImage(
                    url: isBlocked ? nil : comment.comment.avatarSrc,
                    size: nestingLevel > 0 ? theme.replyAvatarSize : theme.avatarSize,
                    showOnlineIndicator: !isBlocked,
                    isOnline: comment.isOnline,
                    onlineIdentifier: "online-\(comment.comment.id)"
                )
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isBlocked)

            VStack(alignment: .leading, spacing: 2) {
                // Display label above username
                if let displayLabel = comment.comment.displayLabel, !displayLabel.isEmpty, !isBlocked {
                    Text(displayLabel)
                        .font(theme.resolveCaptionFont())
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 5) {
                    Button {
                        onUserClick?(.comment(comment.comment), UserInfo.from(comment.comment), .name)
                    } label: {
                        Text(comment.comment.isBlocked == true
                             ? NSLocalizedString("blocked_user", bundle: .module, comment: "")
                             : comment.comment.commenterName)
                            .font(theme.resolveCommenterNameFont())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isBlocked)
                    .accessibilityIdentifier("commenter-name-\(comment.comment.id)")

                    if comment.comment.isPinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("pin-icon-\(comment.comment.id)")
                    }

                    if comment.comment.isLocked == true {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("lock-icon-\(comment.comment.id)")
                    }

                    if let badges = comment.comment.badges, !isBlocked {
                        ForEach(badges) { badge in
                            BadgeView(badge: badge)
                        }
                    }

                    // Unverified badge
                    if !sdk.disableUnverifiedLabel && !(comment.comment.verified ?? true) && !isBlocked {
                        Text(NSLocalizedString("unverified", bundle: .module, comment: ""))
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            #if os(iOS)
                            .background(Color(uiColor: .systemGray6))
                            #else
                            .background(Color(nsColor: .controlBackgroundColor))
                            #endif
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }

                if let date = comment.comment.date {
                    Text(RelativeDateFormatter.format(date))
                        .font(theme.resolveCaptionFont())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Context menu
            Menu {
                if canEdit {
                    Button { onEdit?(comment) } label: {
                        Label(NSLocalizedString("edit", bundle: .module, comment: ""), systemImage: "pencil")
                    }
                }
                if canDelete {
                    Button(role: .destructive) { onDelete?(comment) } label: {
                        Label(NSLocalizedString("delete", bundle: .module, comment: ""), systemImage: "trash")
                    }
                }
                if sdk.isSiteAdmin {
                    Button { onPin?(comment) } label: {
                        Label(
                            comment.comment.isPinned == true
                                ? NSLocalizedString("unpin", bundle: .module, comment: "")
                                : NSLocalizedString("pin", bundle: .module, comment: ""),
                            systemImage: comment.comment.isPinned == true ? "pin.slash" : "pin"
                        )
                    }
                    Button { onLock?(comment) } label: {
                        Label(
                            comment.comment.isLocked == true
                                ? NSLocalizedString("unlock", bundle: .module, comment: "")
                                : NSLocalizedString("lock", bundle: .module, comment: ""),
                            systemImage: comment.comment.isLocked == true ? "lock.open" : "lock"
                        )
                    }
                }
                if !isOwnComment {
                    Button { onBlock?(comment) } label: {
                        Label(
                            comment.comment.isBlocked == true
                                ? NSLocalizedString("unblock_user", bundle: .module, comment: "")
                                : NSLocalizedString("block_user", bundle: .module, comment: ""),
                            systemImage: comment.comment.isBlocked == true ? "hand.raised.slash" : "hand.raised"
                        )
                    }
                }
                if !isOwnComment && !isBlocked {
                    Button { onFlag?(comment) } label: {
                        Label(
                            comment.comment.isFlagged == true
                                ? NSLocalizedString("unflag", bundle: .module, comment: "")
                                : NSLocalizedString("flag", bundle: .module, comment: ""),
                            systemImage: comment.comment.isFlagged == true ? "flag.slash" : "flag"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("menu-\(comment.comment.id)")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if comment.comment.isBlocked == true {
            Text(NSLocalizedString("blocked_user_message", bundle: .module, comment: ""))
                .font(theme.resolveBodyFont())
                .foregroundStyle(.secondary)
                .italic()
                .accessibilityIdentifier("comment-text-\(comment.comment.id)")
        } else if comment.comment.isDeleted == true {
            Text(NSLocalizedString("comment_deleted", bundle: .module, comment: ""))
                .font(theme.resolveBodyFont())
                .foregroundStyle(.secondary)
                .italic()
                .accessibilityIdentifier("comment-text-\(comment.comment.id)")
        } else {
            HTMLContentView(html: comment.comment.commentHTML)
                .font(theme.resolveBodyFont())
                .accessibilityIdentifier("comment-text-\(comment.comment.id)")
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 16) {
            if !isBlocked {
                VoteControls(
                    comment: comment,
                    voteStyle: voteStyle,
                    onUpVote: {
                        Task { try? await sdk.voteComment(commentId: comment.comment.id, isUpvote: true) }
                    },
                    onDownVote: {
                        Task { try? await sdk.voteComment(commentId: comment.comment.id, isUpvote: false) }
                    },
                    onRemoveVote: {
                        if let voteId = comment.comment.myVoteId {
                            Task { try? await sdk.deleteCommentVote(commentId: comment.comment.id, voteId: voteId) }
                        }
                    }
                )
            }

            if let onReply = onReply, comment.comment.isLocked != true, !sdk.isClosed, !isBlocked {
                Button {
                    onReply(comment)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left")
                        Text(NSLocalizedString("reply", bundle: .module, comment: ""))
                    }
                    .font(theme.resolveActionFont())
                    .foregroundStyle(theme.resolveReplyButtonColor())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reply-\(comment.comment.id)")
            }

            Spacer()

            // Toggle replies
            if let onToggleReplies = onToggleReplies {
                let childCount = comment.comment.childCount ?? comment.comment.children?.count ?? 0
                if childCount > 0 {
                    Button {
                        onToggleReplies(comment)
                    } label: {
                        HStack(spacing: 4) {
                            if comment.isLoadingChildren {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: comment.isRepliesShown ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text(comment.isRepliesShown
                                 ? NSLocalizedString("hide_replies", bundle: .module, comment: "")
                                 : String(format: NSLocalizedString("show_replies_%lld", bundle: .module, comment: ""), childCount)
                            )
                        }
                        .font(theme.resolveActionFont())
                        .foregroundStyle(theme.resolveToggleRepliesButtonColor())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toggle-replies-\(comment.comment.id)")
                }
            }
        }

        // Load more children
        if comment.isRepliesShown && comment.hasMoreChildren {
            Button {
                Task {
                    comment.childSkip += comment.childPageSize
                    comment.childPage += 1
                    let children = try? await sdk.getCommentsForParent(
                        parentId: comment.comment.id,
                        skip: comment.childSkip,
                        limit: comment.childPageSize
                    )
                    if let children = children {
                        sdk.commentsTree.addForParent(parentId: comment.comment.id, comments: children)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text(NSLocalizedString("load_more_replies", bundle: .module, comment: ""))
                }
                .font(theme.resolveActionFont())
                .foregroundStyle(theme.resolveActionButtonColor())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var leadingPadding: CGFloat {
        if nestingLevel == 0 { return 0 }
        return CGFloat(nestingLevel) * theme.nestingIndent
    }

    private var canEdit: Bool {
        guard let userId = sdk.currentUser?.id else { return sdk.isSiteAdmin }
        return comment.comment.userId == userId || sdk.isSiteAdmin
    }

    private var canDelete: Bool {
        canEdit
    }

    private var isOwnComment: Bool {
        guard let userId = sdk.currentUser?.id else { return false }
        return comment.comment.userId == userId
    }

    private var isBlocked: Bool {
        comment.comment.isBlocked == true
    }
}

// MARK: - Comment Style Modifier

private struct CommentStyleModifier: ViewModifier {
    let theme: FastCommentsTheme
    let nestingLevel: Int

    func body(content: Content) -> some View {
        switch theme.commentStyle {
        case .card:
            content
                .background(theme.resolveCommentBackgroundColor())
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius.value))
                .shadow(
                    color: theme.showShadows ? .black.opacity(0.06) : .clear,
                    radius: theme.showShadows ? 8 : 0,
                    y: theme.showShadows ? 2 : 0
                )

        case .bubble:
            content
                .background(theme.resolveCommentBackgroundColor())
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius.value))

        case .flat:
            content
        }
    }
}
