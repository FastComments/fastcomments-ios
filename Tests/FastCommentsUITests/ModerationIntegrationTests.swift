import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class ModerationIntegrationTests: IntegrationTestBase {

    func testFlagAndUnflag() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Flag me")
        try await sdk.flagComment(commentId: comment.id)

        // Verify local state updated
        XCTAssertEqual(sdk.commentsTree.commentsById[comment.id]?.comment.isFlagged, true)

        // Verify persisted
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()
        XCTAssertEqual(sdk2.commentsTree.commentsById[comment.id]?.comment.isFlagged, true)

        // Unflag
        try await sdk.unflagComment(commentId: comment.id)

        // Verify unflag persisted
        let sdk3 = FastCommentsSDK(config: sdk.config)
        try await sdk3.load()
        XCTAssertNotEqual(sdk3.commentsTree.commentsById[comment.id]?.comment.isFlagged, true)
    }

    func testPinAndUnpin() async throws {
        let sdk = makeAdminSDK()
        try await sdk.load()
        let comment = try await sdk.postComment(text: "Pin and unpin me")

        // Pin via SDK
        try await sdk.pinComment(commentId: comment.id)

        // Verify pin persisted on server
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()
        XCTAssertEqual(sdk2.commentsTree.commentsById[comment.id]?.comment.isPinned, true)

        // Unpin via SDK
        try await sdk.unpinComment(commentId: comment.id)

        // Verify unpin persisted on server
        let sdk3 = FastCommentsSDK(config: sdk.config)
        try await sdk3.load()
        XCTAssertNotEqual(sdk3.commentsTree.commentsById[comment.id]?.comment.isPinned, true)
    }

    func testLockAndUnlock() async throws {
        let sdk = makeAdminSDK()
        try await sdk.load()
        let comment = try await sdk.postComment(text: "Lock and unlock me")

        // Lock via SDK
        try await sdk.lockComment(commentId: comment.id)

        // Verify lock persisted on server
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()
        XCTAssertEqual(sdk2.commentsTree.commentsById[comment.id]?.comment.isLocked, true)

        // Unlock via SDK
        try await sdk.unlockComment(commentId: comment.id)

        // Verify unlock persisted on server
        let sdk3 = FastCommentsSDK(config: sdk.config)
        try await sdk3.load()
        XCTAssertNotEqual(sdk3.commentsTree.commentsById[comment.id]?.comment.isLocked, true)
    }

    func testNonAdminCannotPin() async throws {
        let sdk = makeSDK() // regular user, not admin
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Try to pin without admin")

        // pinComment should throw since the non-admin SSO user lacks permission
        do {
            try await sdk.pinComment(commentId: comment.id)
            // If it didn't throw, verify server didn't actually pin
            let sdk2 = FastCommentsSDK(config: sdk.config)
            try await sdk2.load()
            XCTAssertNotEqual(sdk2.commentsTree.commentsById[comment.id]?.comment.isPinned, true,
                              "Non-admin should not be able to pin")
        } catch {
            // Expected — server rejects non-admin pin
        }
    }

    func testNonAdminCannotLock() async throws {
        let sdk = makeSDK() // regular user, not admin
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Try to lock without admin")

        do {
            try await sdk.lockComment(commentId: comment.id)
            let sdk2 = FastCommentsSDK(config: sdk.config)
            try await sdk2.load()
            XCTAssertNotEqual(sdk2.commentsTree.commentsById[comment.id]?.comment.isLocked, true,
                              "Non-admin should not be able to lock")
        } catch {
            // Expected — server rejects non-admin lock
        }
    }

    func testBlockAndUnblock() async throws {
        let urlId = makeUrlId()

        // User A posts a comment
        let sdkA = makeSDK(urlId: urlId)
        try await sdkA.load()
        let comment = try await sdkA.postComment(text: "Block the author of this")

        // User B loads and blocks User A
        let sdkB = makeSDK(urlId: urlId)
        try await sdkB.load()
        try await sdkB.blockUser(commentId: comment.id)

        // Reload from B's perspective — should be blocked on server
        let sdkB2 = FastCommentsSDK(config: sdkB.config)
        try await sdkB2.load()
        XCTAssertEqual(sdkB2.commentsTree.commentsById[comment.id]?.comment.isBlocked, true)

        // Same user B unblocks
        let sdkB3 = FastCommentsSDK(config: sdkB.config)
        try await sdkB3.load()
        try await sdkB3.unblockUser(commentId: comment.id)

        // Reload — should no longer be blocked
        let sdkB4 = FastCommentsSDK(config: sdkB.config)
        try await sdkB4.load()
        XCTAssertNotEqual(sdkB4.commentsTree.commentsById[comment.id]?.comment.isBlocked, true)
    }
}
