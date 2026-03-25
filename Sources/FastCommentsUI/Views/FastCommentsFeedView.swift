import SwiftUI
import FastCommentsSwift

/// Feed view with pull-to-refresh, infinite scroll, and post interaction callbacks.
/// Mirrors FastCommentsFeedView.java from Android.
public struct FastCommentsFeedView: View {
    @ObservedObject var sdk: FastCommentsFeedSDK

    var onPostSelected: ((FeedPost) -> Void)?
    var onCommentsRequested: ((FeedPost) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?
    var onSharePost: ((FeedPost) -> Void)?
    var onMediaClick: ((FeedPostMediaItem, Int) -> Void)?

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
                    Spacer()
                }
            } else if let error = sdk.blockingErrorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else if sdk.feedPosts.isEmpty {
                VStack {
                    Spacer()
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
                .refreshable {
                    try? await sdk.refresh()
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
    }

    // Modifier-style callbacks
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
}
