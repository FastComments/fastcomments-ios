import SwiftUI
import FastCommentsSwift

/// Feed view with pull-to-refresh, infinite scroll, and post interaction callbacks.
public struct FastCommentsFeedView: View {
    @ObservedObject var sdk: FastCommentsFeedSDK

    var onPostSelected: ((FeedPost) -> Void)?
    var onCommentsRequested: ((FeedPost) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?
    var onSharePost: ((FeedPost) -> Void)?
    var onMediaClick: ((FeedPostMediaItem, Int) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var showDeleteAlert: FeedPost?

    public init(sdk: FastCommentsFeedSDK) {
        self.sdk = sdk
    }

    public var body: some View {
        Group {
            if sdk.isLoading && sdk.feedPosts.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                }
            } else if let error = sdk.blockingErrorMessage {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            } else if sdk.feedPosts.isEmpty && sdk.newPostsCount == 0 {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text(NSLocalizedString("no_posts_yet", bundle: .module, comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sdk.feedPosts, id: \.id) { post in
                            FeedPostRowView(
                                post: post,
                                sdk: sdk,
                                onComment: { onCommentsRequested?($0) },
                                onLike: { _ in },
                                onShare: { onSharePost?($0) },
                                onPostClick: { onPostSelected?($0) },
                                onMediaClick: onMediaClick,
                                onUserClick: onUserClick,
                                onDelete: { showDeleteAlert = $0 }
                            )
                            Divider()
                                .padding(.horizontal, theme.feedContentPadding)

                            // Infinite scroll trigger
                            if post.id == sdk.feedPosts.last?.id && sdk.hasMore {
                                ProgressView()
                                    .padding()
                                    .onAppear {
                                        Task { try? await sdk.loadMore() }
                                    }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if sdk.newPostsCount > 0 {
                        NewFeedPostsBanner(count: sdk.newPostsCount) {
                            Task {
                                do {
                                    try await sdk.loadNewPosts()
                                } catch {
                                    // loadNewPosts preserves newPostsCount on failure,
                                    // so the banner stays visible for retry
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    _ = try? await sdk.refresh()
                }
            }
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
                if let post = showDeleteAlert {
                    Task { try? await sdk.deletePost(postId: post.id) }
                }
            }
        }
        .onAppear {
            sdk.resumeLiveUpdates()
        }
        .onDisappear {
            sdk.pauseLiveUpdates()
        }
    }

    // MARK: - Modifier-style API

    public func onPostSelected(_ handler: @escaping (FeedPost) -> Void) -> FastCommentsFeedView {
        var copy = self
        copy.onPostSelected = handler
        return copy
    }

    public func onCommentsRequested(_ handler: @escaping (FeedPost) -> Void) -> FastCommentsFeedView {
        var copy = self
        copy.onCommentsRequested = handler
        return copy
    }

    public func onSharePost(_ handler: @escaping (FeedPost) -> Void) -> FastCommentsFeedView {
        var copy = self
        copy.onSharePost = handler
        return copy
    }

    public func onUserClick(_ handler: @escaping (UserClickContext, UserInfo, UserClickSource) -> Void) -> FastCommentsFeedView {
        var copy = self
        copy.onUserClick = handler
        return copy
    }

    public func onMediaClick(_ handler: @escaping (FeedPostMediaItem, Int) -> Void) -> FastCommentsFeedView {
        var copy = self
        copy.onMediaClick = handler
        return copy
    }
}
