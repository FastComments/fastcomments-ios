import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Social feed with SSO, post creation, comments dialog, error handling, and tag filtering.
///
/// Shows how to:
/// - Create a feed SDK with Simple SSO for user identity
/// - Display the feed with pull-to-refresh
/// - Show a FAB to create new posts with error handling
/// - Open a comments dialog for a post
/// - Refresh the feed after post creation
/// - Filter feed posts using TagSupplier
/// - Register a FollowStateProvider to drive the follow/unfollow pill
/// - Handle errors from feed loading and post creation
struct FeedExampleView: View {
    // 1. Create the feed SDK with SSO so the user can post and react
    @StateObject private var sdk: FastCommentsFeedSDK = {
        let userData = SimpleSSOUserData(
            username: "Example User",
            email: "user@example.com",
            avatar: "https://staticm.fastcomments.com/1639362726066-DSC_0841.JPG"
        )
        let sso = FastCommentsSSO.createSimple(simpleSSOUserData: userData)
        let token = try? sso.prepareToSend()

        let config = FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "test",
            pageTitle: "Feed Example",
            sso: token
        )

        let sdk = FastCommentsFeedSDK(config: config)

        // 2. Optionally filter feed posts by tags.
        //    Return nil or don't set a supplier to get a "global" feed.
        //    Only posts matching these tags will be returned.
        sdk.tagSupplier = ExampleTagSupplier()

        return sdk
    }()

    // 2a. Follow-state provider. Owned here so its lifecycle tracks the view;
    //     the SDK holds a strong ref once assigned. Registered in .task.
    @StateObject private var followProvider = LoggingFollowStateProvider()

    @State private var showCreatePost = false
    @State private var commentsPost: FeedPost?
    @State private var selectedUser: UserInfo?
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 3. Embed the feed view
            FastCommentsFeedView(sdk: sdk)
                .onPostSelected { post in
                    commentsPost = post
                }
                .onSharePost { post in
                    // In a real app, use UIActivityViewController
                    print("Share post: \(post.id)")
                }
                .onCommentsRequested { post in
                    commentsPost = post
                }
                .onUserClick { context, userInfo, source in
                    selectedUser = userInfo
                }
                .task {
                    // 4. Wire up the follow-state provider.
                    sdk.followStateProvider = followProvider

                    // 5. Load with error handling
                    do {
                        try await sdk.loadIfNeeded()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

            // 5. Floating action button to create a new post
            if !showCreatePost {
                Button {
                    showCreatePost = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor.gradient)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
                .padding(20)
            }
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        // 6. Post creation sheet with error/cancel handling
        .sheet(isPresented: $showCreatePost) {
            FeedPostCreateView(
                sdk: sdk,
                onPostCreated: { post in
                    showCreatePost = false
                    // 7. Refresh the feed to show the new post
                    Task { try? await sdk.refresh() }
                },
                onCancelled: {
                    showCreatePost = false
                }
            )
        }
        // 8. Comments dialog for a post
        .sheet(item: $commentsPost) { post in
            CommentsSheet(post: post, feedSDK: sdk, onUserClick: { context, userInfo, source in
                selectedUser = userInfo
            })
        }
        // Error alert
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        // User profile alert
        .alert("User Profile", isPresented: .constant(selectedUser != nil)) {
            Button("OK") { selectedUser = nil }
        } message: {
            if let user = selectedUser {
                Text("Tapped on \(user.displayName)")
            }
        }
    }
}

// MARK: - Tag Supplier Example

/// Example tag supplier that returns nil (global feed).
/// In a real app, return tags to filter the feed for the current user.
///
/// Example returning tags:
/// ```swift
/// func getTags(currentUser: UserSessionInfo?) -> [String]? {
///     guard let user = currentUser else { return nil }
///     return ["team:\(user.id ?? "")", "public"]
/// }
/// ```
struct ExampleTagSupplier: TagSupplier {
    func getTags(currentUser: UserSessionInfo?) -> [String]? {
        // Return nil for a global (unfiltered) feed.
        // Return specific tags to only show posts matching those tags.
        return nil
    }
}

// FeedPost needs Identifiable for .sheet(item:)
extension FeedPost: @retroactive Identifiable {}

// MARK: - Follow State Provider Example

/// Demo `FollowStateProvider` that keeps state purely in-memory and simulates
/// a 3-second backend round-trip before invoking the callback. Every call is
/// logged via `print(...)` so the behavior is observable from Xcode's console.
///
/// In a real app, replace the `Task.sleep` with an actual network request
/// (e.g. `POST /users/{id}/follow`) and invoke `result(...)` with the server's
/// response — or with the unchanged state on failure, to revert the optimistic
/// UI update.
@MainActor
final class LoggingFollowStateProvider: ObservableObject, FollowStateProvider {

    /// In-memory follow cache. Keyed by user id.
    private var followingUserIds: Set<String> = []

    nonisolated init() {}

    func isFollowing(_ user: UserInfo) -> Bool {
        guard let id = user.userId else { return false }
        let following = followingUserIds.contains(id)
        print("[FollowProvider] isFollowing user=\(user.displayName) id=\(id) -> \(following)")
        return following
    }

    func requestFollowStateChange(
        for user: UserInfo,
        desiredFollowing: Bool,
        result: @escaping @Sendable (Bool) -> Void
    ) {
        let userId = user.userId ?? ""
        print("[FollowProvider] request user=\(user.displayName) id=\(userId) desired=\(desiredFollowing) — simulating 3s backend call")

        // Weak capture so the provider isn't kept alive purely by an
        // in-flight request after the viewer navigates away.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }

            if desiredFollowing {
                self.followingUserIds.insert(userId)
            } else {
                self.followingUserIds.remove(userId)
            }

            print("[FollowProvider] complete user=\(user.displayName) nowFollowing=\(desiredFollowing)")
            result(desiredFollowing)
        }
    }
}
