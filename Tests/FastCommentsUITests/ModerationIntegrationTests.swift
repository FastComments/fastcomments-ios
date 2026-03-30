import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class ModerationIntegrationTests: IntegrationTestBase {

    func testFlagComment() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Flag me")
        try await sdk.flagComment(commentId: comment.id)

        // Reload and verify the flag was recorded
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()
        let renderable = sdk2.commentsTree.commentsById[comment.id]
        XCTAssertNotNil(renderable)
        XCTAssertEqual(renderable?.comment.isFlagged, true)
    }

    func testPinCommentViaAdminAPI() async throws {
        let sdk = makeSDK()
        try await sdk.load()
        let comment = try await sdk.postComment(text: "Pin me")

        // Pin via authenticated admin API (SDK public pin has a response parsing bug)
        _ = try await DefaultAPI.updateComment(
            tenantId: tenantId,
            id: comment.id,
            updatableCommentParams: UpdatableCommentParams(isPinned: true),
            apiConfiguration: adminApiConfig
        )

        // Reload and verify
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()
        let renderable = sdk2.commentsTree.commentsById[comment.id]
        XCTAssertNotNil(renderable)
        XCTAssertEqual(renderable?.comment.isPinned, true)
    }

    func testLockCommentViaAdminAPI() async throws {
        let sdk = makeSDK()
        try await sdk.load()
        let comment = try await sdk.postComment(text: "Lock me")

        _ = try await DefaultAPI.updateComment(
            tenantId: tenantId,
            id: comment.id,
            updatableCommentParams: UpdatableCommentParams(isLocked: true),
            apiConfiguration: adminApiConfig
        )

        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()
        let renderable = sdk2.commentsTree.commentsById[comment.id]
        XCTAssertNotNil(renderable)
        XCTAssertEqual(renderable?.comment.isLocked, true)
    }

    func testBlockUserViaSDK() async throws {
        let urlId = makeUrlId()

        // User A posts a comment
        let sdkA = makeSDK(urlId: urlId)
        try await sdkA.load()
        let comment = try await sdkA.postComment(text: "Block the author of this")

        // User B blocks user A from this comment
        let sdkB = makeSDK(urlId: urlId)
        try await sdkB.load()
        try await sdkB.blockUser(commentId: comment.id)
    }
}
