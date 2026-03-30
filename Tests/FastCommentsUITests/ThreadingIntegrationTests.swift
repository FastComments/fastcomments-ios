import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class ThreadingIntegrationTests: IntegrationTestBase {

    func testNestedReplies() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let root = try await sdk.postComment(text: "Root")
        let child = try await sdk.postComment(text: "Child", parentId: root.id)
        let grandchild = try await sdk.postComment(text: "Grandchild", parentId: child.id)

        XCTAssertEqual(sdk.commentCountOnServer, 3)
        XCTAssertEqual(grandchild.parentId, child.id)
        XCTAssertEqual(child.parentId, root.id)
        XCTAssertNil(root.parentId)
    }

    func testDeleteMidLevelCascades() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let root = try await sdk.postComment(text: "Root")
        let child = try await sdk.postComment(text: "Child", parentId: root.id)
        let grandchild = try await sdk.postComment(text: "Grandchild", parentId: child.id)

        try await sdk.deleteComment(commentId: child.id)

        // Child removed
        XCTAssertNil(sdk.commentsTree.commentsById[child.id])
        // Grandchild also cascade-removed from local tree
        XCTAssertNil(sdk.commentsTree.commentsById[grandchild.id])
        // Root should still exist
        XCTAssertNotNil(sdk.commentsTree.commentsById[root.id])
    }

    func testChildCountUpdated() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let root = try await sdk.postComment(text: "Parent")
        _ = try await sdk.postComment(text: "Reply 1", parentId: root.id)
        _ = try await sdk.postComment(text: "Reply 2", parentId: root.id)

        // Reload to see server-side child count
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()

        let parent = sdk2.commentsTree.commentsById[root.id]
        XCTAssertNotNil(parent)
        // The parent should indicate it has children
        let childCount = parent?.comment.childCount ?? 0
        XCTAssertGreaterThanOrEqual(childCount, 2)
    }

    func testReplyToReply() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let root = try await sdk.postComment(text: "Level 0")
        let level1 = try await sdk.postComment(text: "Level 1", parentId: root.id)
        let level2 = try await sdk.postComment(text: "Level 2", parentId: level1.id)
        let level3 = try await sdk.postComment(text: "Level 3", parentId: level2.id)

        XCTAssertEqual(sdk.commentCountOnServer, 4)
        XCTAssertEqual(level3.parentId, level2.id)
        XCTAssertEqual(level2.parentId, level1.id)
        XCTAssertEqual(level1.parentId, root.id)
    }

    func testDeleteLeafPreservesThread() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let root = try await sdk.postComment(text: "Root")
        let child1 = try await sdk.postComment(text: "Child 1", parentId: root.id)
        let child2 = try await sdk.postComment(text: "Child 2", parentId: root.id)

        try await sdk.deleteComment(commentId: child1.id)

        XCTAssertNil(sdk.commentsTree.commentsById[child1.id])
        XCTAssertNotNil(sdk.commentsTree.commentsById[child2.id])
        XCTAssertNotNil(sdk.commentsTree.commentsById[root.id])
    }

    func testDeleteRootRemovesEntireThread() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let root = try await sdk.postComment(text: "Root")
        let child = try await sdk.postComment(text: "Child", parentId: root.id)
        let grandchild = try await sdk.postComment(text: "Grandchild", parentId: child.id)

        try await sdk.deleteComment(commentId: root.id)

        XCTAssertNil(sdk.commentsTree.commentsById[root.id])
        XCTAssertNil(sdk.commentsTree.commentsById[child.id])
        XCTAssertNil(sdk.commentsTree.commentsById[grandchild.id])
    }

    func testLoadChildrenPagination() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let root = try await sdk.postComment(text: "Parent with many replies")
        for i in 1...4 {
            _ = try await sdk.postComment(text: "Reply \(i)", parentId: root.id)
        }

        // Reload to get the server-side tree structure with children
        let sdk2 = FastCommentsSDK(config: sdk.config)
        try await sdk2.load()

        let parent = sdk2.commentsTree.commentsById[root.id]
        XCTAssertNotNil(parent, "Parent comment should exist after reload")

        // Parent should have children or a childCount indicating children exist
        let childCount = parent?.comment.childCount ?? 0
        let loadedChildren = parent?.comment.children?.count ?? 0
        XCTAssertTrue(childCount > 0 || loadedChildren > 0,
                       "Parent should have children (childCount=\(childCount), loaded=\(loadedChildren))")
    }
}
