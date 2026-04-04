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
    @State private var showBlockAlert: RenderableComment?
    /// Number of nodes rendered in the ForEach. Grows when the user scrolls
    /// up to load older messages, and shrinks back when they return to the bottom.
    @State private var renderWindow: Int = 500
    private static let defaultRenderWindow = 500

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

                            ForEach(windowedNodes, id: \.id) { node in
                                rowView(for: node)
                                    .id(node.id)
                            }

                            // Native bottom = visual top. Triggers loading older messages.
                            if hasOlderToShow {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .flipped()
                                    .onAppear {
                                        expandWindowOrLoadMore()
                                    }
                            }
                        }
                    }
                    .flipped()
                    .onChange(of: sdk.commentsTree.visibleNodes.count) { _ in
                        // Auto-scroll to newest only if user is near the bottom
                        // In rotated space, anchor: .top = visual bottom
                        if isNearBottom && !isLoadingOlder {
                            // Shrink window back to default when at bottom,
                            // so old nodes far off-screen are released.
                            if renderWindow > Self.defaultRenderWindow {
                                renderWindow = Self.defaultRenderWindow
                            }
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
        .alert(
            showBlockAlert?.comment.isBlocked == true
                ? NSLocalizedString("unblock_user_title", bundle: .module, comment: "")
                : NSLocalizedString("block_user_title", bundle: .module, comment: ""),
            isPresented: Binding(
                get: { showBlockAlert != nil },
                set: { if !$0 { showBlockAlert = nil } }
            )
        ) {
            Button(NSLocalizedString("cancel", bundle: .module, comment: ""), role: .cancel) {}
            Button(
                showBlockAlert?.comment.isBlocked == true
                    ? NSLocalizedString("unblock_user", bundle: .module, comment: "")
                    : NSLocalizedString("block_user", bundle: .module, comment: ""),
                role: showBlockAlert?.comment.isBlocked == true ? nil : .destructive
            ) {
                if let comment = showBlockAlert {
                    Task {
                        do {
                            if comment.comment.isBlocked == true {
                                try await sdk.unblockUser(commentId: comment.comment.id)
                            } else {
                                try await sdk.blockUser(commentId: comment.comment.id)
                            }
                        } catch { sdk.showWarning(error.localizedDescription) }
                    }
                }
            }
        } message: {
            if let comment = showBlockAlert {
                Text(String(
                    format: comment.comment.isBlocked == true
                        ? NSLocalizedString("unblock_user_confirm", bundle: .module, comment: "")
                        : NSLocalizedString("block_user_confirm", bundle: .module, comment: ""),
                    comment.comment.commenterName
                ))
            }
        }
    }

    // MARK: - Windowing

    /// The slice of visible nodes to actually render, taken from the end of the full list
    /// and reversed for the flipped ScrollView layout.
    private var windowedNodes: [RenderableNode] {
        let all = sdk.commentsTree.visibleNodes
        let start = max(0, all.count - renderWindow)
        // Reversed because the ScrollView is flipped: native top = visual bottom.
        return Array(all[start...].reversed())
    }

    /// Whether there are older messages to show (either un-rendered local nodes, or more on server).
    private var hasOlderToShow: Bool {
        sdk.commentsTree.visibleNodes.count > renderWindow || sdk.hasMore
    }

    /// Either expand the render window (if there are un-rendered local nodes) or fetch from server.
    private func expandWindowOrLoadMore() {
        let totalNodes = sdk.commentsTree.visibleNodes.count
        if renderWindow < totalNodes {
            // Show more from already-loaded data
            renderWindow = min(renderWindow + 500, totalNodes)
        } else {
            // All local nodes are shown; fetch from server
            loadOlderMessages()
        }
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
                    onUserClick: onUserClick,
                    onBlock: { comment in
                        showBlockAlert = comment
                    }
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
