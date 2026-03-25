import SwiftUI
import FastCommentsSwift

/// Main comments view displaying a threaded comment list with input bar.
/// Mirrors FastCommentsView.java from Android.
public struct FastCommentsView: View {
    @ObservedObject var sdk: FastCommentsSDK
    var voteStyle: VoteStyle = ._0

    var onCommentPosted: ((PublicComment) -> Void)?
    var onReplyClick: ((RenderableComment) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var replyingTo: RenderableComment?
    @State private var editingComment: RenderableComment?
    @State private var showDeleteAlert: RenderableComment?

    public init(sdk: FastCommentsSDK, voteStyle: VoteStyle = ._0) {
        self.sdk = sdk
        self.voteStyle = voteStyle
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if sdk.isLoading && sdk.commentsTree.visibleNodes.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error = sdk.blockingErrorMessage {
                    Spacer()
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else if sdk.commentsTree.visibleNodes.isEmpty {
                    Spacer()
                    Text(NSLocalizedString("no_comments_yet", bundle: .module, comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sdk.commentsTree.visibleNodes) { node in
                                nodeView(for: node)
                            }
                        }
                    }

                    PaginationControls(
                        sdk: sdk,
                        onLoadMore: { try? await sdk.loadMore() },
                        onLoadAll: { try? await sdk.loadAll() }
                    )
                }
            }
            .padding(.bottom, 60) // Space for input bar

            // Comment input
            if !sdk.isClosed {
                CommentInputBar(
                    sdk: sdk,
                    replyingTo: $replyingTo,
                    onCommentPosted: { comment in
                        onCommentPosted?(comment)
                    }
                )
            }
        }
        .demoBanner(isDemo: sdk.isDemo)
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
            Divider().padding(.leading, 12)
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

// Make RenderableComment conform to Identifiable for .sheet(item:)
extension RenderableComment: @retroactive Hashable {
    public static func == (lhs: RenderableComment, rhs: RenderableComment) -> Bool {
        lhs.id == rhs.id
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
