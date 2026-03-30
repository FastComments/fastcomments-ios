import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class LiveEventIntegrationTests: IntegrationTestBase {

    func testLiveNewCommentAppears() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeSDK(urlId: urlId)
        try await sdk1.load()
        XCTAssertEqual(sdk1.commentsTree.totalSize(), 0)

        let sdk2 = makeSDK(urlId: urlId)
        try await sdk2.load()
        let posted = try await sdk2.postComment(text: "Live comment")

        try await waitFor(timeout: 5.0) {
            sdk1.commentsTree.commentsById[posted.id] != nil
        }

        XCTAssertNotNil(sdk1.commentsTree.commentsById[posted.id])

        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLiveCommentShowsRightAway() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeSDK(urlId: urlId)
        sdk1.showLiveRightAway = true
        try await sdk1.load()

        let sdk2 = makeSDK(urlId: urlId)
        try await sdk2.load()
        let posted = try await sdk2.postComment(text: "Show right away")

        try await waitFor(timeout: 5.0) {
            sdk1.commentsTree.commentsById[posted.id] != nil
        }

        let isVisible = sdk1.commentsTree.visibleNodes.contains { $0.id == posted.id }
        XCTAssertTrue(isVisible)

        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLiveCommentBuffered() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeSDK(urlId: urlId)
        sdk1.showLiveRightAway = false
        try await sdk1.load()

        let sdk2 = makeSDK(urlId: urlId)
        try await sdk2.load()
        let posted = try await sdk2.postComment(text: "Buffered comment")

        try await waitFor(timeout: 5.0) {
            sdk1.commentsTree.commentsById[posted.id] != nil
        }

        let hasButton = sdk1.commentsTree.visibleNodes.contains { $0 is RenderableButton }
        XCTAssertTrue(hasButton)

        sdk1.commentsTree.showNewRootComments()

        let isVisible = sdk1.commentsTree.visibleNodes.contains { $0.id == posted.id }
        XCTAssertTrue(isVisible)

        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLiveDeleteRemoves() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeSDK(urlId: urlId)
        try await sdk1.load()

        let sdk2 = makeSDK(urlId: urlId)
        try await sdk2.load()
        let posted = try await sdk2.postComment(text: "To be deleted live")

        try await waitFor(timeout: 5.0) {
            sdk1.commentsTree.commentsById[posted.id] != nil
        }

        try await sdk2.deleteComment(commentId: posted.id)

        try await waitFor(timeout: 5.0) {
            sdk1.commentsTree.commentsById[posted.id] == nil
        }

        XCTAssertNil(sdk1.commentsTree.commentsById[posted.id])

        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLiveVoteUpdates() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeSDK(urlId: urlId)
        try await sdk1.load()
        let comment = try await sdk1.postComment(text: "Vote on me live")

        let sdk2 = makeSDK(urlId: urlId)
        try await sdk2.load()
        _ = try await sdk2.voteComment(commentId: comment.id, isUpvote: true)

        try await waitFor(timeout: 5.0) {
            let c = sdk1.commentsTree.commentsById[comment.id]
            return (c?.comment.votesUp ?? 0) >= 1
        }

        let renderable = sdk1.commentsTree.commentsById[comment.id]!
        XCTAssertGreaterThanOrEqual(renderable.comment.votesUp ?? 0, 1)

        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testBroadcastIdPreventsOwnEcho() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Own comment")

        // Wait briefly for any live events to arrive
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let count = sdk.commentsTree.allComments.filter { $0.id == comment.id }.count
        XCTAssertEqual(count, 1)

        sdk.cleanup()
    }

    func testLiveReplyAppears() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeSDK(urlId: urlId)
        try await sdk1.load()
        let root = try await sdk1.postComment(text: "Root for live reply")

        let sdk2 = makeSDK(urlId: urlId)
        try await sdk2.load()
        let reply = try await sdk2.postComment(text: "Live reply", parentId: root.id)

        try await waitFor(timeout: 5.0) {
            sdk1.commentsTree.commentsById[reply.id] != nil
        }

        let replyRenderable = sdk1.commentsTree.commentsById[reply.id]
        XCTAssertNotNil(replyRenderable)
        XCTAssertEqual(replyRenderable?.comment.parentId, root.id)

        sdk1.cleanup()
        sdk2.cleanup()
    }

    func testLiveCommentCountUpdates() async throws {
        let urlId = makeUrlId()

        let sdk1 = makeSDK(urlId: urlId)
        try await sdk1.load()
        let initialCount = sdk1.commentCountOnServer

        let sdk2 = makeSDK(urlId: urlId)
        try await sdk2.load()
        _ = try await sdk2.postComment(text: "Increment count")

        try await waitFor(timeout: 5.0) {
            sdk1.commentCountOnServer > initialCount
        }

        XCTAssertEqual(sdk1.commentCountOnServer, initialCount + 1)

        sdk1.cleanup()
        sdk2.cleanup()
    }
}
