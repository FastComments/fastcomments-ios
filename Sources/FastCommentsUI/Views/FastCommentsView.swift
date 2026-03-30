import SwiftUI
import FastCommentsSwift

/// Main comments view displaying a threaded comment list with input bar.
public struct FastCommentsView: View {
    @ObservedObject var sdk: FastCommentsSDK
    var voteStyle: VoteStyle = ._0
    var customToolbarButtons: [any CustomToolbarButton] = []

    var onCommentPosted: ((PublicComment) -> Void)?
    var onReplyClick: ((RenderableComment) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var replyingTo: RenderableComment?
    @State private var editingComment: RenderableComment?
    @State private var showDeleteAlert: RenderableComment?

    public init(sdk: FastCommentsSDK, voteStyle: VoteStyle = ._0, customToolbarButtons: [any CustomToolbarButton] = []) {
        self.sdk = sdk
        self.voteStyle = voteStyle
        self.customToolbarButtons = customToolbarButtons
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if sdk.isLoading && sdk.commentsTree.visibleNodes.isEmpty {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = sdk.blockingErrorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else if sdk.commentsTree.visibleNodes.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundStyle(.quaternary)
                        Text(NSLocalizedString("no_comments_yet", bundle: .module, comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: theme.commentSpacing) {
                            ForEach(sdk.commentsTree.visibleNodes) { node in
                                nodeView(for: node)
                            }
                        }
                        .padding(.vertical, theme.commentStyle == .card ? 8 : 0)

                        PaginationControls(
                            sdk: sdk,
                            onLoadMore: { try? await sdk.loadMore() },
                            onLoadAll: { try? await sdk.loadAll() }
                        )
                    }
                }
            }
            .padding(.bottom, 60) // Space for input bar

            // Comment input
            if !sdk.isClosed {
                CommentInputBar(
                    sdk: sdk,
                    replyingTo: $replyingTo,
                    customToolbarButtons: customToolbarButtons,
                    onCommentPosted: { comment in
                        onCommentPosted?(comment)
                    }
                )
            } else {
                Text(NSLocalizedString("comments_closed", bundle: .module, comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.resolveInputBarBackgroundColor())
            }
        }
        .demoBanner(isDemo: sdk.isDemo, warningMessage: sdk.warningMessage)
        .sheet(item: $editingComment) { comment in
            CommentEditSheet(
                currentText: comment.comment.commentHTML,
                onSave: { newText in
                    Task { try? await sdk.editComment(commentId: comment.comment.id, newText: newText) }
                }
            )
        }
        .alert(
            NSLocalizedString("delete_confirm", bundle: .module, comment: ""),
            isPresented: Binding(
                get: { showDeleteAlert != nil },
                set: { if !$0 { showDeleteAlert = nil } }
            )
        ) {
            Button(NSLocalizedString("cancel", bundle: .module, comment: ""), role: .cancel) {}
            Button(NSLocalizedString("delete", bundle: .module, comment: ""), role: .destructive) {
                if let comment = showDeleteAlert {
                    Task { try? await sdk.deleteComment(commentId: comment.comment.id) }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { sdk.badgeAwardToShow != nil },
            set: { if !$0 { sdk.badgeAwardToShow = nil } }
        )) {
            if let badges = sdk.badgeAwardToShow {
                BadgeAwardSheet(badges: badges)
            }
        }
    }

    @ViewBuilder
    private func nodeView(for node: RenderableNode) -> some View {
        if let comment = node as? RenderableComment {
            CommentRowView(
                comment: comment,
                sdk: sdk,
                nestingLevel: comment.nestingLevel(in: sdk.commentsTree.commentsById),
                voteStyle: voteStyle,
                onReply: { comment in
                    replyingTo = comment
                    onReplyClick?(comment)
                },
                onToggleReplies: { comment in
                    Task {
                        await sdk.commentsTree.toggleRepliesVisible(comment) { request in
                            try await sdk.getCommentsForParent(
                                parentId: request.parentId,
                                skip: request.skip ?? 0,
                                limit: request.limit ?? 5
                            )
                        }
                    }
                },
                onUserClick: onUserClick,
                onEdit: { editingComment = $0 },
                onDelete: { showDeleteAlert = $0 },
                onFlag: { comment in
                    Task { try? await sdk.flagComment(commentId: comment.comment.id) }
                }
            )

            if theme.commentStyle == .flat {
                Divider()
                    .padding(.leading, 14)
            }
        } else if let button = node as? RenderableButton {
            NewCommentsButton(button: button) {
                switch button.buttonType {
                case .newRootComments:
                    sdk.commentsTree.showNewRootComments()
                case .newChildComments:
                    if let parentId = button.parentId {
                        sdk.commentsTree.showNewChildComments(parentId: parentId)
                    }
                }
            }
        } else if let separator = node as? DateSeparator {
            DateSeparatorRow(separator: separator)
        }
    }
}

// MARK: - Modifier-style API

extension FastCommentsView {
    /// Handle user avatar/name taps.
    public func onUserClick(_ handler: @escaping (UserClickContext, UserInfo, UserClickSource) -> Void) -> FastCommentsView {
        var copy = self
        copy.onUserClick = handler
        return copy
    }

    /// Called when a comment is successfully posted.
    public func onCommentPosted(_ handler: @escaping (PublicComment) -> Void) -> FastCommentsView {
        var copy = self
        copy.onCommentPosted = handler
        return copy
    }

    /// Called when the reply button is tapped.
    public func onReplyClick(_ handler: @escaping (RenderableComment) -> Void) -> FastCommentsView {
        var copy = self
        copy.onReplyClick = handler
        return copy
    }
}

// Make RenderableComment conform to Identifiable for .sheet(item:)
extension RenderableComment: Hashable {
    public static func == (lhs: RenderableComment, rhs: RenderableComment) -> Bool {
        lhs.id == rhs.id
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
