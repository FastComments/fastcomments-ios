import SwiftUI
import FastCommentsSwift

/// Live chat view with auto-scroll to bottom, date separators, and compact comment layout.
/// Mirrors LiveChatView.java from Android.
public struct LiveChatView: View {
    @ObservedObject var sdk: FastCommentsSDK
    var voteStyle: VoteStyle = ._1

    var onCommentPosted: ((PublicComment) -> Void)?
    var onCommentDeleted: ((String) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?

    @State private var replyingTo: RenderableComment?
    @State private var autoScrollToBottom = true

    public init(sdk: FastCommentsSDK) {
        self.sdk = sdk
        // Configure SDK for live chat
        sdk.commentsTree.liveChatStyle = true
        sdk.defaultSortDirection = .of
        sdk.showLiveRightAway = true
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sdk.commentsTree.visibleNodes) { node in
                            if let comment = node as? RenderableComment {
                                CommentRowView(
                                    comment: comment,
                                    sdk: sdk,
                                    nestingLevel: 0,
                                    voteStyle: voteStyle,
                                    onReply: { replyingTo = $0 },
                                    onToggleReplies: nil,
                                    onUserClick: onUserClick
                                )
                            } else if let separator = node as? DateSeparator {
                                DateSeparatorRow(separator: separator)
                            }
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .onChange(of: sdk.commentsTree.visibleNodes.count) { _, _ in
                    if autoScrollToBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            CommentInputBar(
                sdk: sdk,
                replyingTo: $replyingTo,
                onCommentPosted: { comment in
                    onCommentPosted?(comment)
                }
            )
        }
        .demoBanner(isDemo: sdk.isDemo)
    }
}
