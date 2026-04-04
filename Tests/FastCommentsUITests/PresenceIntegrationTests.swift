import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class PresenceIntegrationTests: IntegrationTestBase {

    override var stableTenantEmail: String { "ios-presence@fctest.com" }

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

    // MARK: - WebSocket Presence Tests

    /// Equivalent to Android's testUserBJoinVisibleToUserA.
    /// SDK2 loads and posts a comment, then SDK1 loads on the same page.
    /// Since SDK2 is connected via WebSocket, SDK1 should see SDK2's comment as online.
    func testPresenceOnJoin() async throws {
        let urlId = makeUrlId()

        // SDK2 loads first and posts a comment
        let sdk2 = makeSDK(urlId: urlId)
        addTeardownBlock { sdk2.cleanup() }
        try await sdk2.load()
        let posted = try await sdk2.postComment(text: "Presence join test")

        // SDK1 loads on same urlId — initial response includes SDK2's comment.
        // On WS connect, SDK1 calls fetchUserPresenceStatuses for visible users.
        let sdk1 = makeSDK(urlId: urlId)
        addTeardownBlock { sdk1.cleanup() }
        try await sdk1.load()

        // SDK2's comment should be in SDK1's tree from the initial load
        let commentInSdk1 = try XCTUnwrap(
            sdk1.commentsTree.commentsById[posted.id],
            "SDK1 should have SDK2's comment from initial load"
        )

        // Since SDK2 is connected via WebSocket, the presence fetch should report online
        try await waitFor(timeout: 10.0) {
            commentInSdk1.isOnline
        }

        XCTAssertTrue(commentInSdk1.isOnline, "SDK2's comment should show as online")
    }

    /// Equivalent to Android's testUserBReconnectVisibleToUserA.
    /// SDK2 connects, goes online, disconnects, then reconnects with the same identity.
    /// SDK1 should see the user go offline and then come back online.
    func testPresenceRestoredAfterReconnect() async throws {
        let urlId = makeUrlId()
        let userId2 = UUID().uuidString

        // SDK2 loads with a stable user identity and posts a comment
        var sdk2: FastCommentsSDK? = makeSDK(urlId: urlId, userId: userId2)
        addTeardownBlock { sdk2?.cleanup() }
        try await sdk2!.load()
        let posted = try await sdk2!.postComment(text: "Presence reconnect test")

        // SDK1 loads, sees comment, connects to WS
        let sdk1 = makeSDK(urlId: urlId)
        addTeardownBlock { sdk1.cleanup() }
        try await sdk1.load()

        let commentInSdk1 = try XCTUnwrap(
            sdk1.commentsTree.commentsById[posted.id],
            "SDK1 should have SDK2's comment"
        )

        // Wait for online
        try await waitFor(timeout: 10.0) {
            commentInSdk1.isOnline
        }
        XCTAssertTrue(commentInSdk1.isOnline, "Initially online")

        // SDK2 disconnects
        sdk2!.cleanup()
        sdk2 = nil

        // Server sends p-u with ul (user left) — SDK1 should see offline
        try await waitFor(timeout: 15.0) {
            !commentInSdk1.isOnline
        }
        XCTAssertFalse(commentInSdk1.isOnline, "Offline after disconnect")

        // SDK2 reconnects with the same user identity
        let sdk2b = makeSDK(urlId: urlId, userId: userId2)
        addTeardownBlock { sdk2b.cleanup() }
        try await sdk2b.load()

        // Server sends p-u with uj (user joined) — SDK1 should see online again
        try await waitFor(timeout: 10.0) {
            commentInSdk1.isOnline
        }
        XCTAssertTrue(commentInSdk1.isOnline, "Online again after reconnect")
    }
}
