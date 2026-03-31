import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Social feed view for UI testing — driven entirely by launch arguments.
struct TestFeedView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @State private var commentsPost: FeedPost?

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsFeedSDK(config: config))
    }

    var body: some View {
        FastCommentsFeedView(sdk: sdk)
            .onCommentsRequested { post in
                commentsPost = post
            }
            .task {
                try? await sdk.load()
            }
            .sheet(item: $commentsPost) { post in
                CommentsSheet(post: post, feedSDK: sdk)
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
    }
}
