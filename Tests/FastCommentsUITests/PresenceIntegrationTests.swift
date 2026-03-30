import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class PresenceIntegrationTests: IntegrationTestBase {

    func testClearAllPresence() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        _ = try await sdk.postComment(text: "Comment 1")
        _ = try await sdk.postComment(text: "Comment 2")

        // Server-posted comments should have userId indexed
        XCTAssertFalse(sdk.commentsTree.commentsByUserId.isEmpty, "commentsByUserId should be populated from server data")

        // Set all online via the presence API
        let userId = sdk.commentsTree.commentsByUserId.keys.first!
        sdk.commentsTree.updateUserPresence(userId: userId, isOnline: true)
        XCTAssertTrue(sdk.commentsTree.allComments.contains { $0.isOnline })

        // Clear all presence
        sdk.commentsTree.clearAllPresence()

        for comment in sdk.commentsTree.allComments {
            XCTAssertFalse(comment.isOnline, "All comments should be offline after clearAllPresence")
        }

        sdk.cleanup()
    }

    func testPresenceIndexingAndPropagation() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        _ = try await sdk.postComment(text: "Comment A")
        _ = try await sdk.postComment(text: "Comment B")

        // Verify userId is indexed in commentsByUserId
        let userIds = Array(sdk.commentsTree.commentsByUserId.keys)
        XCTAssertFalse(userIds.isEmpty, "commentsByUserId should have entries from server-posted comments")

        let userId = userIds.first!
        let commentsForUser = sdk.commentsTree.commentsByUserId[userId]!
        XCTAssertGreaterThanOrEqual(commentsForUser.count, 2, "Both comments should be indexed under the same userId")

        // Set online and verify all comments for that user update
        sdk.commentsTree.updateUserPresence(userId: userId, isOnline: true)
        for comment in commentsForUser {
            XCTAssertTrue(comment.isOnline, "All comments by user should be online after updateUserPresence")
        }

        // Set offline
        sdk.commentsTree.updateUserPresence(userId: userId, isOnline: false)
        for comment in commentsForUser {
            XCTAssertFalse(comment.isOnline, "All comments by user should be offline after setting offline")
        }

        sdk.cleanup()
    }
}
