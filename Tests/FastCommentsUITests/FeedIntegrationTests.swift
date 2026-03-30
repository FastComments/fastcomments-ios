import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class FeedIntegrationTests: IntegrationTestBase {

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

        try await feedSDK.reactPost(postId: post.id, reactionType: "like")

        XCTAssertTrue(feedSDK.hasUserReacted(postId: post.id, reactType: "like"))
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
        try await feedSDK.reactPost(postId: post.id, reactionType: "like")
        XCTAssertTrue(feedSDK.hasUserReacted(postId: post.id, reactType: "like"))

        // Unreact (toggle)
        try await feedSDK.reactPost(postId: post.id, reactionType: "like")
        XCTAssertFalse(feedSDK.hasUserReacted(postId: post.id, reactType: "like"))
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
        try await feedSDK.reactPost(postId: post.id, reactionType: "like")

        let savedState = feedSDK.savePaginationState()

        // Create a new feed SDK and restore
        let feedSDK2 = makeFeedSDK()
        feedSDK2.restorePaginationState(savedState)

        XCTAssertEqual(feedSDK2.feedPosts.count, feedSDK.feedPosts.count)
        XCTAssertEqual(feedSDK2.hasMore, feedSDK.hasMore)
        XCTAssertEqual(feedSDK2.getLikeCount(postId: post.id), 1)
        XCTAssertTrue(feedSDK2.hasUserReacted(postId: post.id, reactType: "like"))

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

        XCTAssertEqual(commentsSDK.config.urlId, post.id)
        XCTAssertEqual(commentsSDK.config.tenantId, tenantId)

        // Cleanup
        try? await feedSDK.deletePost(postId: post.id)
        feedSDK.cleanup()
    }
}
