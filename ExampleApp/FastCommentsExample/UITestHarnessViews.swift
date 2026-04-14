import SwiftUI
import FastCommentsUI
import FastCommentsSwift

struct TestFeedView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @State private var showCreatePost = false

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsFeedSDK(config: config))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FastCommentsFeedView(sdk: sdk)

            Button {
                showCreatePost = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("open-feed-post-composer")
            .padding(20)
        }
        .sheet(isPresented: $showCreatePost) {
            FeedPostCreateView(
                sdk: sdk,
                onPostCreated: { _ in
                    showCreatePost = false
                    Task { try? await sdk.refresh() }
                },
                onCancelled: {
                    showCreatePost = false
                }
            )
        }
        .task { try? await sdk.loadIfNeeded() }
        .navigationTitle("Feed Test")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TestCommentsView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsSDK

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsSDK(config: config))
    }

    var body: some View {
        FastCommentsView(sdk: sdk)
            .task { try? await sdk.load() }
            .navigationTitle("Test")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedComposerTestView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @State private var createdPost: FeedPost?

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsFeedSDK(config: config))
    }

    var body: some View {
        FeedPostCreateView(
            sdk: sdk,
            onPostCreated: { post in
                createdPost = post
            }
        )
        .safeAreaInset(edge: .bottom) {
            if let createdPost {
                Text(createdPost.contentHTML ?? "")
                    .accessibilityIdentifier("feed-created-post-content")
                    .padding(.bottom, 8)
            }
        }
        .task { try? await sdk.loadIfNeeded() }
    }
}

struct FullFeedComposerTestView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @State private var showCreatePost = false

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsFeedSDK(config: config))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FastCommentsFeedView(sdk: sdk)

            Button {
                showCreatePost = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("open-feed-post-composer")
            .padding(20)
        }
        .sheet(isPresented: $showCreatePost) {
            FeedPostCreateView(
                sdk: sdk,
                onPostCreated: { _ in
                    showCreatePost = false
                    Task { try? await sdk.refresh() }
                },
                onCancelled: {
                    showCreatePost = false
                }
            )
        }
        .task { try? await sdk.loadIfNeeded() }
    }
}

/// Harness for follow-button UI tests. Registers an in-memory
/// `FollowStateProvider` that flips after a short delay so UI tests can assert
/// both the optimistic transition and the confirmed state. Used with the
/// `-follow-test` launch argument.
struct TestFollowView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @StateObject private var followProvider = TestFollowStateProvider(delayNanos: 500_000_000)

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsFeedSDK(config: config))
    }

    var body: some View {
        FastCommentsFeedView(sdk: sdk)
            .task {
                sdk.followStateProvider = followProvider
                try? await sdk.loadIfNeeded()
            }
            .navigationTitle("Follow Test")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Parity harness: mirrors the real `FeedExampleView` demo — same modifier
/// chain on `FastCommentsFeedView`, same 3-second provider delay — so a UI
/// test can assert multi-post sync under conditions identical to what a
/// human sees in the demo.
struct TestFollowDemoParityView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @StateObject private var followProvider = TestFollowStateProvider(delayNanos: 3_000_000_000)

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsFeedSDK(config: config))
    }

    var body: some View {
        FastCommentsFeedView(sdk: sdk)
            .onPostSelected { _ in }
            .onSharePost { _ in }
            .onCommentsRequested { _ in }
            .onUserClick { _, _, _ in }
            .task {
                sdk.followStateProvider = followProvider
                try? await sdk.loadIfNeeded()
            }
            .navigationTitle("Follow Demo Parity")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// In-memory `FollowStateProvider` for UI tests. Confirms changes after a
/// configurable delay — the fast harness uses 500ms to observe optimistic +
/// confirmed states quickly, while the demo-parity harness uses 3s to match
/// the shipping `LoggingFollowStateProvider` exactly.
@MainActor
final class TestFollowStateProvider: ObservableObject, FollowStateProvider {
    private let delayNanos: UInt64
    private var followingUserIds: Set<String> = []

    nonisolated init(delayNanos: UInt64) {
        self.delayNanos = delayNanos
    }

    func isFollowing(_ user: UserInfo) -> Bool {
        guard let id = user.userId else { return false }
        return followingUserIds.contains(id)
    }

    func requestFollowStateChange(
        for user: UserInfo,
        desiredFollowing: Bool,
        result: @escaping @Sendable (Bool) -> Void
    ) {
        let userId = user.userId ?? ""
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.delayNanos ?? 0)
            guard let self else { return }
            if desiredFollowing {
                self.followingUserIds.insert(userId)
            } else {
                self.followingUserIds.remove(userId)
            }
            result(desiredFollowing)
        }
    }
}

struct FeedLifecycleTestView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @State private var isFeedVisible = true

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        let sdk = FastCommentsFeedSDK(config: config)
        sdk.pageSize = 2
        _sdk = StateObject(wrappedValue: sdk)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(isFeedVisible ? "Hide Feed" : "Show Feed") {
                    isFeedVisible.toggle()
                }
                .accessibilityIdentifier("feed-lifecycle-toggle")

                Button("Load More") {
                    Task { _ = try? await sdk.loadMore() }
                }
                .accessibilityIdentifier("feed-lifecycle-load-more")
                .disabled(!sdk.hasMore)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Text("\(sdk.feedPosts.count)")
                .accessibilityIdentifier("feed-lifecycle-count")

            Text(sdk.feedPosts.last?.id ?? "none")
                .accessibilityIdentifier("feed-lifecycle-last-id")

            Text(sdk.feedPosts.last?.contentHTML ?? "none")
                .accessibilityIdentifier("feed-lifecycle-last-text")

            if isFeedVisible {
                FastCommentsFeedView(sdk: sdk)
                    .accessibilityIdentifier("feed-lifecycle-view")
            } else {
                Text("Feed hidden")
                    .accessibilityIdentifier("feed-lifecycle-hidden")
                Spacer()
            }
        }
        .task { try? await sdk.loadIfNeeded() }
        .navigationTitle("Feed Lifecycle")
        .navigationBarTitleDisplayMode(.inline)
    }
}
