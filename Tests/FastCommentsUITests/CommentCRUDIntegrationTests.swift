import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class CommentCRUDIntegrationTests: IntegrationTestBase {

    override var stableTenantEmail: String { "ios-comment-crud@fctest.com" }

    // MARK: - Load

    func testLoadEmptyPage() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        XCTAssertEqual(sdk.commentCountOnServer, 0)
        XCTAssertEqual(sdk.commentsTree.totalSize(), 0)
        XCTAssertTrue(sdk.commentsTree.visibleNodes.isEmpty)
        XCTAssertFalse(sdk.hasMore)
        XCTAssertNil(sdk.blockingErrorMessage)
    }

    func testPostComment() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Hello from iOS test")

        XCTAssertEqual(sdk.commentCountOnServer, 1)
        XCTAssertEqual(sdk.commentsTree.totalSize(), 1)
        XCTAssertNotNil(sdk.commentsTree.commentsById[comment.id])
        XCTAssertTrue(comment.commentHTML.contains("Hello from iOS test"))
    }

    func testPostCommentReturnsValidComment() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Test comment content")

        XCTAssertFalse(comment.id.isEmpty)
        XCTAssertTrue(comment.commentHTML.contains("Test comment content"))
        XCTAssertNotNil(comment.date)
    }

    func testPostReply() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let parent = try await sdk.postComment(text: "Parent comment")
        let reply = try await sdk.postComment(text: "Reply to parent", parentId: parent.id)

        XCTAssertEqual(sdk.commentCountOnServer, 2)
        XCTAssertEqual(reply.parentId, parent.id)
        XCTAssertNotNil(sdk.commentsTree.commentsById[reply.id])
    }

    func testPostEmptyCommentThrows() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        do {
            _ = try await sdk.postComment(text: "")
            XCTFail("Expected error for empty comment text")
        } catch {
            // Expected — empty text validation is local, no auth needed
        }

        do {
            _ = try await sdk.postComment(text: "   ")
            XCTFail("Expected error for whitespace-only comment text")
        } catch {
            // Expected
        }
    }

    // MARK: - Edit

    func testEditComment() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Original text")
        XCTAssertTrue(comment.commentHTML.contains("Original text"))

        try await sdk.editComment(commentId: comment.id, newText: "Edited text")

        // Local tree should be updated immediately with server-rendered HTML
        let renderable = sdk.commentsTree.commentsById[comment.id]
        XCTAssertNotNil(renderable)
        XCTAssertTrue(renderable!.comment.commentHTML.contains("Edited text"))

        // Reload on fresh SDK to verify persistence
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()
        let reloaded = sdk2.commentsTree.commentsById[comment.id]
        XCTAssertNotNil(reloaded)
        XCTAssertTrue(reloaded!.comment.commentHTML.contains("Edited text"))
    }

    // MARK: - Delete

    func testDeleteComment() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "To be deleted")
        XCTAssertEqual(sdk.commentCountOnServer, 1)

        try await sdk.deleteComment(commentId: comment.id)

        XCTAssertEqual(sdk.commentCountOnServer, 0)
        XCTAssertNil(sdk.commentsTree.commentsById[comment.id])
        XCTAssertEqual(sdk.commentsTree.totalSize(), 0)
    }

    func testDeleteCommentWithReplies() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let parent = try await sdk.postComment(text: "Parent")
        _ = try await sdk.postComment(text: "Child", parentId: parent.id)
        XCTAssertEqual(sdk.commentCountOnServer, 2)

        try await sdk.deleteComment(commentId: parent.id)

        XCTAssertNil(sdk.commentsTree.commentsById[parent.id])
    }

    // MARK: - Pagination

    func testPaginationViaLoadMore() async throws {
        let totalComments = 35
        let sdk = makeSDK()
        try await sdk.load()

        // Create 35 root comments (exceeds default pageSize of 30)
        for i in 1...totalComments {
            _ = try await sdk.postComment(text: "Comment \(i)")
        }

        // Reload fresh with default page size
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()

        let firstPageSize = sdk2.commentsTree.totalSize()
        print("[FC] Pagination test: firstPage=\(firstPageSize) hasMore=\(sdk2.hasMore) commentCountOnServer=\(sdk2.commentCountOnServer)")

        XCTAssertGreaterThan(firstPageSize, 0, "First page should have comments")
        XCTAssertTrue(sdk2.hasMore, "35 comments with default pageSize 30 should have more")

        // Load next page
        try await sdk2.loadMore()
        let afterLoadMore = sdk2.commentsTree.totalSize()
        print("[FC] Pagination test: afterLoadMore=\(afterLoadMore) hasMore=\(sdk2.hasMore)")

        XCTAssertGreaterThan(afterLoadMore, firstPageSize, "loadMore should have fetched additional comments")
        XCTAssertEqual(afterLoadMore, totalComments, "All 35 comments should now be loaded")
        XCTAssertFalse(sdk2.hasMore, "No more pages after loading all")
    }

    func testLoadAll() async throws {
        let totalComments = 35
        let sdk = makeSDK()
        try await sdk.load()

        for i in 1...totalComments {
            _ = try await sdk.postComment(text: "Comment \(i)")
        }

        // Reload then loadAll to fetch everything at once
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()

        let firstPageSize = sdk2.commentsTree.totalSize()
        XCTAssertTrue(sdk2.hasMore, "Should have more before loadAll")

        try await sdk2.loadAll()

        XCTAssertEqual(sdk2.commentsTree.totalSize(), totalComments)
        XCTAssertFalse(sdk2.hasMore)
    }

    func testPostMultipleRootComments() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let c1 = try await sdk.postComment(text: "First")
        let c2 = try await sdk.postComment(text: "Second")
        let c3 = try await sdk.postComment(text: "Third")

        XCTAssertEqual(sdk.commentCountOnServer, 3)
        XCTAssertEqual(sdk.commentsTree.totalSize(), 3)
        XCTAssertNotNil(sdk.commentsTree.commentsById[c1.id])
        XCTAssertNotNil(sdk.commentsTree.commentsById[c2.id])
        XCTAssertNotNil(sdk.commentsTree.commentsById[c3.id])
    }
}
