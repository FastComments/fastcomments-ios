import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class FeedIntegrationTests: IntegrationTestBase {

    override var stableTenantEmail: String { "ios-feed@fctest.com" }

    private func seedPosts(count: Int, urlId: String) async throws -> [FeedPost] {
        let seedSDK = makeFeedSDK(urlId: urlId)
        defer { seedSDK.cleanup() }

        _ = try? await seedSDK.load()

        var posts: [FeedPost] = []
        for index in 0..<count {
            var lastError: Error?
            var createdPost: FeedPost?

            for attempt in 0..<3 {
                do {
                    createdPost = try await seedSDK.createPost(
                        params: CreateFeedPostParams(
                            title: "Seed \(index)",
                            contentHTML: "<p>Seed \(index)</p>"
                        )
                    )
                    break
                } catch {
                    lastError = error
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
            }

            if let createdPost {
                posts.append(createdPost)
            } else if let lastError {
                throw lastError
            }
        }
        return posts
    }

    func testLoadFeed() async throws {
        let feedSDK = makeFeedSDK()
        try await feedSDK.load()

        // Should not error — feed may be empty or have existing posts
        XCTAssertNil(feedSDK.blockingErrorMessage)
        XCTAssertFalse(feedSDK.isLoading)

        feedSDK.cleanup()
    }

    func testCreateFeedPost() async throws {
        let feedSDK = makeFeedSDK()
        try await feedSDK.load()

        let params = CreateFeedPostParams(
            title: "Test Feed Post",
            contentHTML: "<p>Test content</p>"
        )
        let post = try await feedSDK.createPost(params: params)

        XCTAssertFalse(post.id.isEmpty)
        XCTAssertEqual(post.title, "Test Feed Post")
        XCTAssertEqual(feedSDK.feedPosts.first?.id, post.id, "New post should be at top of feed")

        // Cleanup feed post
        try? await feedSDK.deletePost(postId: post.id)
        feedSDK.cleanup()
    }

    func testDeleteFeedPost() async throws {
        let feedSDK = makeFeedSDK()
        try await feedSDK.load()

        let params = CreateFeedPostParams(
            title: "To Delete",
            contentHTML: "<p>Will be deleted</p>"
        )
        let post = try await feedSDK.createPost(params: params)
        XCTAssertTrue(feedSDK.feedPosts.contains { $0.id == post.id })

        try await feedSDK.deletePost(postId: post.id)

        XCTAssertFalse(feedSDK.feedPosts.contains { $0.id == post.id })

        feedSDK.cleanup()
    }

    func testReactPost() async throws {
        let feedSDK = makeFeedSDK()
        try await feedSDK.load()

        let params = CreateFeedPostParams(
            title: "React to me",
            contentHTML: "<p>Like this post</p>"
        )
        let post = try await feedSDK.createPost(params: params)

        try await feedSDK.reactPost(postId: post.id, reactionType: "l")

        XCTAssertTrue(feedSDK.hasUserReacted(postId: post.id, reactType: "l"))
        XCTAssertEqual(feedSDK.getLikeCount(postId: post.id), 1)

        // Cleanup
        try? await feedSDK.deletePost(postId: post.id)
        feedSDK.cleanup()
    }

    func testUnreactPost() async throws {
        let feedSDK = makeFeedSDK()
        try await feedSDK.load()

        let params = CreateFeedPostParams(
            title: "Toggle react",
            contentHTML: "<p>Like then unlike</p>"
        )
        let post = try await feedSDK.createPost(params: params)

        // React
        try await feedSDK.reactPost(postId: post.id, reactionType: "l")
        XCTAssertTrue(feedSDK.hasUserReacted(postId: post.id, reactType: "l"))

        // Unreact (toggle)
        try await feedSDK.reactPost(postId: post.id, reactionType: "l")
        XCTAssertFalse(feedSDK.hasUserReacted(postId: post.id, reactType: "l"))
        XCTAssertEqual(feedSDK.getLikeCount(postId: post.id), 0)

        // Cleanup
        try? await feedSDK.deletePost(postId: post.id)
        feedSDK.cleanup()
    }

    func testSaveRestorePaginationState() async throws {
        let feedSDK = makeFeedSDK()
        try await feedSDK.load()

        let params = CreateFeedPostParams(
            title: "State test",
            contentHTML: "<p>For state serialization</p>"
        )
        let post = try await feedSDK.createPost(params: params)

        // React so we have like state to verify
        try await feedSDK.reactPost(postId: post.id, reactionType: "l")

        let savedState = feedSDK.savePaginationState()

        // Create a new feed SDK and restore
        let feedSDK2 = makeFeedSDK()
        feedSDK2.restorePaginationState(savedState)

        XCTAssertEqual(feedSDK2.feedPosts.count, feedSDK.feedPosts.count)
        XCTAssertEqual(feedSDK2.hasMore, feedSDK.hasMore)
        XCTAssertEqual(feedSDK2.getLikeCount(postId: post.id), 1)
        XCTAssertTrue(feedSDK2.hasUserReacted(postId: post.id, reactType: "l"))

        // Cleanup
        try? await feedSDK.deletePost(postId: post.id)
        feedSDK.cleanup()
        feedSDK2.cleanup()
    }

    func testCreateCommentsSDKForPost() async throws {
        let feedSDK = makeFeedSDK()
        try await feedSDK.load()

        let params = CreateFeedPostParams(
            title: "Post with comments",
            contentHTML: "<p>Comment on this</p>"
        )
        let post = try await feedSDK.createPost(params: params)

        let commentsSDK = feedSDK.createCommentsSDK(for: post)

        XCTAssertEqual(commentsSDK.config.urlId, "post:" + post.id)
        XCTAssertEqual(commentsSDK.config.tenantId, tenantId)

        // Cleanup
        try? await feedSDK.deletePost(postId: post.id)
        feedSDK.cleanup()
    }

    func testLoadIfNeededAfterRestoreDoesNotResetPaginationState() async throws {
        let urlId = makeUrlId()
        _ = try await seedPosts(count: 7, urlId: urlId)

        let feedSDK = makeFeedSDK(urlId: urlId)
        feedSDK.pageSize = 3
        try await feedSDK.load()
        try await feedSDK.loadMore()

        let loadedIds = feedSDK.feedPosts.map(\.id)
        let savedState = feedSDK.savePaginationState()

        let restoredSDK = makeFeedSDK(urlId: urlId)
        restoredSDK.restorePaginationState(savedState)
        try await restoredSDK.loadIfNeeded()

        XCTAssertEqual(restoredSDK.feedPosts.map(\.id), loadedIds)
        XCTAssertEqual(restoredSDK.feedPosts.count, 6)
        XCTAssertEqual(restoredSDK.savePaginationState().lastPostId, savedState.lastPostId)

        feedSDK.cleanup()
        restoredSDK.cleanup()
    }

    func testConcurrentLoadMoreDoesNotDuplicatePosts() async throws {
        let urlId = makeUrlId()
        _ = try await seedPosts(count: 7, urlId: urlId)

        let feedSDK = makeFeedSDK(urlId: urlId)
        feedSDK.pageSize = 3
        try await feedSDK.load()

        async let firstLoad: Void = {
            _ = try? await feedSDK.loadMore()
        }()
        async let secondLoad: Void = {
            _ = try? await feedSDK.loadMore()
        }()
        _ = await (firstLoad, secondLoad)

        let ids = feedSDK.feedPosts.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "loadMore should not append duplicate posts")
        XCTAssertEqual(feedSDK.feedPosts.count, 6)

        feedSDK.cleanup()
    }

    func testHasMoreBecomesFalseAfterShortFinalPage() async throws {
        let urlId = makeUrlId()
        _ = try await seedPosts(count: 5, urlId: urlId)

        let feedSDK = makeFeedSDK(urlId: urlId)
        feedSDK.pageSize = 3
        try await feedSDK.load()

        XCTAssertTrue(feedSDK.hasMore)

        try await feedSDK.loadMore()

        XCTAssertFalse(feedSDK.hasMore)
        XCTAssertEqual(feedSDK.feedPosts.count, 5)

        feedSDK.cleanup()
    }

    func testPauseAndResumeLiveUpdatesPreservesPaginationState() async throws {
        let urlId = makeUrlId()
        _ = try await seedPosts(count: 7, urlId: urlId)

        let feedSDK = makeFeedSDK(urlId: urlId)
        feedSDK.pageSize = 3
        try await feedSDK.load()
        try await feedSDK.loadMore()
        let loadedIds = feedSDK.feedPosts.map(\.id)

        feedSDK.pauseLiveUpdates()
        feedSDK.resumeLiveUpdates()

        XCTAssertEqual(feedSDK.feedPosts.map(\.id), loadedIds)
        XCTAssertEqual(feedSDK.feedPosts.count, 6)
        XCTAssertEqual(feedSDK.savePaginationState().lastPostId, loadedIds.last)

        feedSDK.cleanup()
    }
}
