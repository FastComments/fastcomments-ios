import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class PresenceIntegrationTests: IntegrationTestBase {

    func testPresenceAfterLoad() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Presence check")

        let renderable = sdk.commentsTree.commentsById[comment.id]
        XCTAssertNotNil(renderable)
        // isOnline defaults to false until presence is fetched
        XCTAssertFalse(renderable!.isOnline)

        sdk.cleanup()
    }

    func testClearAllPresence() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        _ = try await sdk.postComment(text: "User A comment")
        _ = try await sdk.postComment(text: "User A comment 2")

        // Set all comments to online
        for comment in sdk.commentsTree.allComments {
            comment.isOnline = true
        }
        XCTAssertTrue(sdk.commentsTree.allComments.allSatisfy { $0.isOnline })

        sdk.commentsTree.clearAllPresence()

        for comment in sdk.commentsTree.allComments {
            XCTAssertFalse(comment.isOnline, "All comments should be offline after clearAllPresence")
        }

        sdk.cleanup()
    }

    func testPresenceByUserId() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        _ = try await sdk.postComment(text: "Comment 1")
        _ = try await sdk.postComment(text: "Comment 2")

        // SSO user should have a userId on their comments
        let userIds = Set(sdk.commentsTree.allComments.compactMap { $0.comment.userId ?? $0.comment.anonUserId })
        XCTAssertFalse(userIds.isEmpty, "Comments should have a userId or anonUserId")

        let userId = userIds.first!
        sdk.commentsTree.updateUserPresence(userId: userId, isOnline: true)

        let commentsForUser = sdk.commentsTree.allComments.filter {
            $0.comment.userId == userId || $0.comment.anonUserId == userId
        }
        XCTAssertGreaterThanOrEqual(commentsForUser.count, 2)
        for comment in commentsForUser {
            XCTAssertTrue(comment.isOnline, "All comments by user should be online")
        }

        sdk.cleanup()
    }

    func testAnonUserPresence() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        _ = try await sdk.postComment(text: "Anon comment")

        let allUserIds = Array(sdk.commentsTree.commentsByUserId.keys)
        XCTAssertFalse(allUserIds.isEmpty, "commentsByUserId should have entries after posting")

        sdk.cleanup()
    }
}
