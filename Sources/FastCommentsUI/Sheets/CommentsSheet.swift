import SwiftUI
import FastCommentsSwift

/// Modal sheet displaying comments for a feed post.
/// Mirrors CommentsDialog.java from Android.
public struct CommentsSheet: View {
    let post: FeedPost
    @ObservedObject var feedSDK: FastCommentsFeedSDK
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?

    @StateObject private var commentsSDK: FastCommentsSDK
    @Environment(\.dismiss) private var dismiss

    public init(post: FeedPost, feedSDK: FastCommentsFeedSDK,
                onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)? = nil) {
        self.post = post
        self.feedSDK = feedSDK
        self.onUserClick = onUserClick
        self._commentsSDK = StateObject(wrappedValue: feedSDK.createCommentsSDK(for: post))
    }

    public var body: some View {
        NavigationStack {
            FastCommentsView(sdk: commentsSDK)
                .navigationTitle(NSLocalizedString("comments", bundle: .module, comment: ""))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .task {
                    try? await commentsSDK.load()
                }
        }
        .onDisappear {
            commentsSDK.cleanup()
            Task { try? await feedSDK.fetchPostStats(postIds: [post.id]) }
        }
    }
}
