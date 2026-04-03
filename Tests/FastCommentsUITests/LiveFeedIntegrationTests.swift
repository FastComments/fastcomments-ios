import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class LiveFeedIntegrationTests: IntegrationTestBase {

    override var stableTenantEmail: String { "ios-live-feed@fctest.com" }

    func testLiveNewFeedPostIncrementsCount() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeFeedSDK(urlId: urlId)
        try await sdk1.load()
        XCTAssertEqual(sdk1.newPostsCount, 0)

        let sdk2 = makeFeedSDK(urlId: urlId)
        try await sdk2.load()

        let initialCount = sdk1.feedPosts.count

        let params = CreateFeedPostParams(
            title: "Live post from sdk2",
            contentHTML: "<p>Hello from sdk2</p>"
        )
        let post = try await sdk2.createPost(params: params)

        // sdk1 should see the new post count increment via WebSocket, not auto-insert
        try await waitFor(timeout: 10.0) {
            sdk1.newPostsCount >= 1
        }

        XCTAssertGreaterThanOrEqual(sdk1.newPostsCount, 1)
        // Post should NOT be auto-inserted into feedPosts
        XCTAssertEqual(sdk1.feedPosts.count, initialCount,
                       "New live posts should be buffered, not auto-inserted")

        // Cleanup
        try? await sdk2.deletePost(postId: post.id)
        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLoadNewPostsShowsBufferedPosts() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeFeedSDK(urlId: urlId)
        try await sdk1.load()

        let sdk2 = makeFeedSDK(urlId: urlId)
        try await sdk2.load()

        let params = CreateFeedPostParams(
            title: "Buffered live post",
            contentHTML: "<p>Should appear after loadNewPosts</p>"
        )
        let post = try await sdk2.createPost(params: params)

        // Wait for the count to increment
        try await waitFor(timeout: 10.0) {
            sdk1.newPostsCount >= 1
        }

        // Now load the new posts
        try await sdk1.loadNewPosts()

        XCTAssertEqual(sdk1.newPostsCount, 0, "Count should reset after loading")
        XCTAssertTrue(sdk1.feedPosts.contains { $0.id == post.id },
                      "Buffered post should now appear in feed after loadNewPosts")

        // Cleanup
        try? await sdk1.deletePost(postId: post.id)
        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLiveDeleteRemovesFeedPost() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeFeedSDK(urlId: urlId)
        try await sdk1.load()

        let sdk2 = makeFeedSDK(urlId: urlId)
        try await sdk2.load()

        let params = CreateFeedPostParams(
            title: "Will be deleted",
            contentHTML: "<p>Ephemeral post</p>"
        )
        let post = try await sdk2.createPost(params: params)

        // Load new posts on sdk1 so it has the post
        try await waitFor(timeout: 10.0) {
            sdk1.newPostsCount >= 1
        }
        try await sdk1.loadNewPosts()
        XCTAssertTrue(sdk1.feedPosts.contains { $0.id == post.id })

        // sdk2 deletes it
        try await sdk2.deletePost(postId: post.id)

        // sdk1 should see it removed via live event
        try await waitFor(timeout: 10.0) {
            !sdk1.feedPosts.contains { $0.id == post.id }
        }

        XCTAssertFalse(sdk1.feedPosts.contains { $0.id == post.id },
                       "Deleted post should be removed from feed via live event")

        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLiveUpdateModifiesFeedPost() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeFeedSDK(urlId: urlId)
        try await sdk1.load()

        let sdk2 = makeFeedSDK(urlId: urlId)
        try await sdk2.load()

        let params = CreateFeedPostParams(
            title: "Original title",
            contentHTML: "<p>Original content</p>"
        )
        let post = try await sdk2.createPost(params: params)

        // Load new posts on sdk1
        try await waitFor(timeout: 10.0) {
            sdk1.newPostsCount >= 1
        }
        try await sdk1.loadNewPosts()
        XCTAssertTrue(sdk1.feedPosts.contains { $0.id == post.id })

        // sdk2 reacts to the post — this triggers an updatedFeedPost live event
        try await sdk2.reactPost(postId: post.id, reactionType: "l")

        // Wait for sdk1 to see the update via live event
        try await waitFor(timeout: 10.0) {
            let p = sdk1.feedPosts.first { $0.id == post.id }
            return (p?.reacts?["l"] ?? 0) >= 1
        }

        let updated = sdk1.feedPosts.first { $0.id == post.id }
        XCTAssertNotNil(updated)
        XCTAssertGreaterThanOrEqual(updated?.reacts?["l"] ?? 0, 1,
                                    "Updated post should reflect new reaction count")

        // Cleanup
        try? await sdk2.deletePost(postId: post.id)
        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testBroadcastIdPreventsOwnFeedPostEcho() async throws {
        let sdk = makeFeedSDK()
        try await sdk.load()

        let params = CreateFeedPostParams(
            title: "Own post",
            contentHTML: "<p>Should not echo</p>"
        )
        let post = try await sdk.createPost(params: params)

        // Wait briefly for any live events
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // newPostsCount should still be 0 — our own post should not trigger the banner
        XCTAssertEqual(sdk.newPostsCount, 0,
                       "Own posts should be filtered by broadcastId, not counted as new")

        // The post should be in feedPosts from the direct insert in createPost
        let count = sdk.feedPosts.filter { $0.id == post.id }.count
        XCTAssertEqual(count, 1, "Own post should appear exactly once")

        // Cleanup
        try? await sdk.deletePost(postId: post.id)
        sdk.cleanup()
    }

    func testMultipleLivePostsIncrementCount() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeFeedSDK(urlId: urlId)
        try await sdk1.load()

        let sdk2 = makeFeedSDK(urlId: urlId)
        try await sdk2.load()

        let post1 = try await sdk2.createPost(params: CreateFeedPostParams(
            title: "Post 1", contentHTML: "<p>First</p>"
        ))
        let post2 = try await sdk2.createPost(params: CreateFeedPostParams(
            title: "Post 2", contentHTML: "<p>Second</p>"
        ))

        try await waitFor(timeout: 10.0) {
            sdk1.newPostsCount >= 2
        }

        XCTAssertGreaterThanOrEqual(sdk1.newPostsCount, 2,
                                    "Multiple new posts should each increment the count")

        // Load them all
        try await sdk1.loadNewPosts()
        XCTAssertEqual(sdk1.newPostsCount, 0)
        XCTAssertTrue(sdk1.feedPosts.contains { $0.id == post1.id })
        XCTAssertTrue(sdk1.feedPosts.contains { $0.id == post2.id })

        // Cleanup
        try? await sdk2.deletePost(postId: post1.id)
        try? await sdk2.deletePost(postId: post2.id)
        sdk1.cleanup()
        sdk2.cleanup()
    }
}
