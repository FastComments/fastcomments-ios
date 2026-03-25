import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Feed with custom toolbar buttons on the post creation form.
///
/// Shows how to:
/// - Implement the FeedCustomToolbarButton protocol
/// - Add custom buttons to the feed post creation toolbar
struct FeedCustomButtonsExampleView: View {
    @StateObject private var sdk = FastCommentsFeedSDK(
        config: FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "example-feed-custom"
        )
    )

    @State private var showCreatePost = false

    var body: some View {
        VStack {
            FastCommentsFeedView(sdk: sdk)

            Button("New Post") {
                showCreatePost = true
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .sheet(isPresented: $showCreatePost) {
            // Pass custom toolbar buttons to the post creation view
            FeedPostCreateView(
                sdk: sdk,
                customToolbarButtons: [HashtagButton()],
                onPostCreated: { _ in showCreatePost = false },
                onCancelled: { showCreatePost = false }
            )
        }
        .task {
            try? await sdk.load()
        }
        .navigationTitle("Feed + Custom Buttons")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Example Custom Button

/// Example: a hashtag button that inserts a # at the cursor position.
struct HashtagButton: FeedCustomToolbarButton {
    let id = "hashtag"
    let iconSystemName = "number"
    let contentDescription = "Add Hashtag"

    func onClick(content: Binding<String>) {
        content.wrappedValue += "#"
    }
}
