import SwiftUI
import FastCommentsSwift

/// Live chat view with auto-scroll to bottom, date separators, and compact comment layout.
/// Uses a rotated ScrollView so the natural top becomes the visual bottom,
/// giving reliable bottom-anchored behavior on iOS 16+.
public struct LiveChatView: View {
    @ObservedObject var sdk: FastCommentsSDK
    var voteStyle: VoteStyle = ._1

    var onCommentPosted: ((PublicComment) -> Void)?
    var onCommentDeleted: ((String) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?

    @State private var isNearBottom = true
    @State private var isLoadingOlder = false

    public init(sdk: FastCommentsSDK) {
        self.sdk = sdk
        sdk.commentsTree.liveChatStyle = true
        sdk.defaultSortDirection = .of
        sdk.showLiveRightAway = true
    }

    public var body: some View {
        VStack(spacing: 0) {
            if sdk.isLoading && sdk.commentsTree.visibleNodes.isEmpty {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Native top = visual bottom. Anchor for "scroll to newest".
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")

                            ForEach(Array(sdk.commentsTree.visibleNodes.enumerated().reversed()), id: \.element.id) { _, node in
                                rowView(for: node)
                                    .id(node.id)
                            }

                            // Native bottom = visual top. Triggers loading older messages.
                            if sdk.hasMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .flipped()
                                    .onAppear {
                                        loadOlderMessages()
                                    }
                            }
                        }
                    }
                    .flipped()
                    .onChange(of: sdk.commentsTree.visibleNodes.count) { _ in
                        // Auto-scroll to newest only if user is near the bottom
                        // In rotated space, anchor: .top = visual bottom
                        if isNearBottom && !isLoadingOlder {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .top)
                            }
                        }
                    }
                }
            }

            if !sdk.isClosed {
                CommentInputBar(
                    sdk: sdk,
                    replyingTo: .constant(nil),
                    onCommentPosted: { comment in
                        onCommentPosted?(comment)
                    }
                )
            }
        }
        .demoBanner(isDemo: sdk.isDemo, warningMessage: sdk.warningMessage)
    }

    // MARK: - Private

    @ViewBuilder
    private func rowView(for node: RenderableNode) -> some View {
        Group {
            if let comment = node as? RenderableComment {
                CommentRowView(
                    comment: comment,
                    sdk: sdk,
                    nestingLevel: 0,
                    voteStyle: voteStyle,
                    onReply: nil,
                    onToggleReplies: nil,
                    onUserClick: onUserClick
                )
            } else if let separator = node as? DateSeparator {
                DateSeparatorRow(separator: separator)
            }
        }
        .flipped()
    }

    private func loadOlderMessages() {
        guard !isLoadingOlder else { return }
        isLoadingOlder = true
        Task {
            try? await sdk.loadMore()
            isLoadingOlder = false
        }
    }
}

// MARK: - Flipped modifier

private extension View {
    /// Flip vertically (180-degree rotation + horizontal mirror to preserve text direction).
    func flipped() -> some View {
        self.rotationEffect(.radians(.pi))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}

// MARK: - Modifier-style API

extension LiveChatView {
    /// Called when a message is sent.
    public func onCommentPosted(_ handler: @escaping (PublicComment) -> Void) -> LiveChatView {
        var copy = self
        copy.onCommentPosted = handler
        return copy
    }

    /// Called when a message is deleted.
    public func onCommentDeleted(_ handler: @escaping (String) -> Void) -> LiveChatView {
        var copy = self
        copy.onCommentDeleted = handler
        return copy
    }

    /// Handle user avatar/name taps.
    public func onUserClick(_ handler: @escaping (UserClickContext, UserInfo, UserClickSource) -> Void) -> LiveChatView {
        var copy = self
        copy.onUserClick = handler
        return copy
    }
}
