import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Social feed with posts, reactions, and media.
///
/// Shows how to:
/// - Create a feed SDK and load posts
/// - Handle post selection, share, and media clicks
/// - Use pull-to-refresh
struct FeedExampleView: View {
    @StateObject private var sdk = FastCommentsFeedSDK(
        config: FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "example-feed"
        )
    )

    @State private var selectedPost: FeedPost?

    var body: some View {
        FastCommentsFeedView(sdk: sdk)
            .onPostSelected { post in
                selectedPost = post
            }
            .onSharePost { post in
                // Share the post using UIActivityViewController or similar
                print("Share post: \(post.id)")
            }
            .onCommentsRequested { post in
                // Navigate to a comments view for this post
                print("View comments for post: \(post.id)")
            }
            .task {
                try? await sdk.load()
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
    }
}
