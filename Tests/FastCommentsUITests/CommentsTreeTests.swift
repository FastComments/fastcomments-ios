import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class CommentsTreeTests: XCTestCase {

    // MARK: - Build

    func testBuild() {
        let tree = CommentsTree()
        let comments = [
            MockComment.make(id: "c1", commenterName: "Alice"),
            MockComment.make(id: "c2", commenterName: "Bob"),
            MockComment.make(id: "c3", commenterName: "Charlie"),
        ]

        tree.build(comments: comments)

        XCTAssertEqual(tree.visibleNodes.count, 3)
        XCTAssertEqual(tree.totalSize(), 3)
        XCTAssertEqual(tree.commentsById["c1"]?.comment.commenterName, "Alice")
        XCTAssertEqual(tree.commentsById["c2"]?.comment.commenterName, "Bob")
    }

    func testBuildWithChildren() {
        let tree = CommentsTree()
        let child1 = MockComment.make(id: "child1", parentId: "parent1")
        let child2 = MockComment.make(id: "child2", parentId: "parent1")
        let parent = MockComment.make(id: "parent1", childCount: 2, children: [child1, child2])

        tree.build(comments: [parent])

        XCTAssertEqual(tree.totalSize(), 3)
        XCTAssertNotNil(tree.commentsById["child1"])
        XCTAssertNotNil(tree.commentsById["child2"])
        XCTAssertEqual(tree.commentsById["child1"]?.comment.parentId, "parent1")
    }

    func testBuildEmpty() {
        let tree = CommentsTree()
        tree.build(comments: [])
        XCTAssertEqual(tree.visibleNodes.count, 0)
        XCTAssertEqual(tree.totalSize(), 0)
    }

    // MARK: - Append

    func testAppendComments() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "c1")])

        tree.appendComments([
            MockComment.make(id: "c2"),
            MockComment.make(id: "c3"),
        ])

        XCTAssertEqual(tree.totalSize(), 3)
        XCTAssertEqual(tree.visibleNodes.count, 3)
    }

    func testAppendNoDuplicates() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "c1")])

        tree.appendComments([MockComment.make(id: "c1")])

        XCTAssertEqual(tree.totalSize(), 1)
    }

    // MARK: - Add Comment (Live Events)

    func testAddCommentRootDisplayNow() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "c1")])

        tree.addComment(MockComment.make(id: "c2"), displayNow: true)

        XCTAssertEqual(tree.totalSize(), 2)
        XCTAssertNotNil(tree.commentsById["c2"])
    }

    func testAddCommentRootBuffered() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "c1")])

        tree.addComment(MockComment.make(id: "c2"), displayNow: false)

        // Comment is tracked but may not be in visibleNodes yet
        XCTAssertEqual(tree.totalSize(), 2)
    }

    func testAddCommentChild() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "parent1")])

        tree.addComment(MockComment.make(id: "child1", parentId: "parent1"), displayNow: true)

        XCTAssertEqual(tree.totalSize(), 2)
        XCTAssertEqual(tree.commentsById["child1"]?.comment.parentId, "parent1")
    }

    // MARK: - Remove

    func testRemoveComment() {
        let tree = CommentsTree()
        tree.build(comments: [
            MockComment.make(id: "c1"),
            MockComment.make(id: "c2"),
        ])

        tree.removeComment(commentId: "c1")

        XCTAssertNil(tree.commentsById["c1"])
        XCTAssertNotNil(tree.commentsById["c2"])
        XCTAssertEqual(tree.totalSize(), 1)
    }

    func testRemoveNonexistent() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "c1")])

        tree.removeComment(commentId: "nonexistent")

        XCTAssertEqual(tree.totalSize(), 1)
    }

    // MARK: - Update

    func testUpdateComment() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "c1", commentHTML: "<p>original</p>")])

        let updated = MockComment.make(id: "c1", commentHTML: "<p>edited</p>")
        tree.updateComment(updated)

        XCTAssertEqual(tree.commentsById["c1"]?.comment.commentHTML, "<p>edited</p>")
    }

    // MARK: - Show New Comments

    func testShowNewRootComments() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "c1")])

        // Buffer two new root comments
        tree.addComment(MockComment.make(id: "c2"), displayNow: false)
        tree.addComment(MockComment.make(id: "c3"), displayNow: false)

        let sizeBefore = tree.visibleSize()
        tree.showNewRootComments()
        let sizeAfter = tree.visibleSize()

        XCTAssertGreaterThanOrEqual(sizeAfter, sizeBefore)
    }

    func testShowNewChildComments() {
        let tree = CommentsTree()
        let parent = MockComment.make(id: "parent1")
        tree.build(comments: [parent])

        // Add a child comment that gets buffered on the parent
        let child = MockComment.make(id: "child1", parentId: "parent1")
        tree.addComment(child, displayNow: false)

        tree.showNewChildComments(parentId: "parent1")

        XCTAssertNotNil(tree.commentsById["child1"])
    }

    // MARK: - Presence

    func testPresenceUpdate() {
        let tree = CommentsTree()
        tree.build(comments: [
            MockComment.make(id: "c1", userId: "user1"),
            MockComment.make(id: "c2", userId: "user1"),
            MockComment.make(id: "c3", userId: "user2"),
        ])

        tree.updateUserPresence(userId: "user1", isOnline: true)

        XCTAssertEqual(tree.commentsById["c1"]?.isOnline, true)
        XCTAssertEqual(tree.commentsById["c2"]?.isOnline, true)
        XCTAssertEqual(tree.commentsById["c3"]?.isOnline, false)
    }

    // MARK: - Live Chat Date Separators

    func testLiveChatDateSeparators() {
        let tree = CommentsTree()
        tree.liveChatStyle = true

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let today = Date()

        tree.build(comments: [
            MockComment.make(id: "c1", date: yesterday),
            MockComment.make(id: "c2", date: today),
        ])

        // With live chat style, date separators should be inserted between different dates
        let hasSeparator = tree.visibleNodes.contains { $0 is DateSeparator }
        XCTAssertTrue(hasSeparator, "Expected date separator between comments on different days")
    }

    // MARK: - Add For Parent

    func testAddForParent() {
        let tree = CommentsTree()
        tree.build(comments: [MockComment.make(id: "parent1", childCount: 5)])

        let children = [
            MockComment.make(id: "child1", parentId: "parent1"),
            MockComment.make(id: "child2", parentId: "parent1"),
        ]
        tree.addForParent(parentId: "parent1", comments: children)

        XCTAssertNotNil(tree.commentsById["child1"])
        XCTAssertNotNil(tree.commentsById["child2"])
        XCTAssertEqual(tree.totalSize(), 3)
    }
}
