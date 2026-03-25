import SwiftUI
import FastCommentsSwift

/// Renders a single comment row with avatar, content, votes, reply controls, and threading indentation.
/// Mirrors CommentViewHolder.java from Android.
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

    @Environment(\.fastCommentsTheme) private var theme
    @State private var showMenu = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: avatar, name, badges, date, menu
            HStack(alignment: .top, spacing: 8) {
                Button {
                    onUserClick?(.comment(comment.comment), UserInfo.from(comment.comment), .avatar)
                } label: {
                    AvatarImage(
                        url: comment.comment.avatarSrc,
                        size: nestingLevel > 0 ? 28 : 36,
                        showOnlineIndicator: true,
                        isOnline: comment.isOnline
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Button {
                            onUserClick?(.comment(comment.comment), UserInfo.from(comment.comment), .name)
                        } label: {
                            Text(comment.comment.commenterName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)

                        if comment.comment.isPinned == true {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }

                        if let badges = comment.comment.badges {
                            ForEach(badges) { badge in
                                BadgeView(badge: badge)
                            }
                        }
                    }

                    if let date = comment.comment.date {
                        Text(RelativeDateFormatter.format(date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                    Button { onFlag?(comment) } label: {
                        Label(NSLocalizedString("flag", bundle: .module, comment: ""), systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }

            // Comment content
            if comment.comment.isDeleted == true {
                Text(NSLocalizedString("comment_deleted", bundle: .module, comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                HTMLContentView(html: comment.comment.commentHTML)
                    .font(.subheadline)
            }

            // Action row: votes, reply, toggle replies
            HStack(spacing: 16) {
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

                if comment.comment.isLocked != true {
                    Button {
                        onReply?(comment)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrowshape.turn.up.left")
                            Text(NSLocalizedString("reply", bundle: .module, comment: ""))
                        }
                        .font(.caption)
                        .foregroundStyle(theme.resolveReplyButtonColor())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Toggle replies
                if let childCount = comment.comment.childCount, childCount > 0 {
                    Button {
                        onToggleReplies?(comment)
                    } label: {
                        HStack(spacing: 2) {
                            if comment.isLoadingChildren {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(comment.isRepliesShown
                                 ? NSLocalizedString("hide_replies", bundle: .module, comment: "")
                                 : String(format: NSLocalizedString("show_replies_%lld", bundle: .module, comment: ""), childCount)
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(theme.resolveToggleRepliesButtonColor())
                    }
                    .buttonStyle(.plain)
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
                    Text(NSLocalizedString("load_more_replies", bundle: .module, comment: ""))
                        .font(.caption)
                        .foregroundStyle(theme.resolveActionButtonColor())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, CGFloat(nestingLevel) * 20)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canEdit: Bool {
        guard let userId = sdk.currentUser?.id else { return sdk.isSiteAdmin }
        return comment.comment.userId == userId || sdk.isSiteAdmin
    }

    private var canDelete: Bool {
        canEdit
    }
}
