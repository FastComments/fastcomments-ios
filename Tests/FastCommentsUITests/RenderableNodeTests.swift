import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class RenderableNodeTests: XCTestCase {

    func testNestingLevelRoot() {
        let comment = RenderableComment(comment: MockComment.make(id: "root"))
        let map: [String: RenderableComment] = ["root": comment]

        XCTAssertEqual(comment.nestingLevel(in: map), 0)
    }

    func testNestingLevelDepth1() {
        let parent = RenderableComment(comment: MockComment.make(id: "parent"))
        let child = RenderableComment(comment: MockComment.make(id: "child", parentId: "parent"))
        let map: [String: RenderableComment] = ["parent": parent, "child": child]

        XCTAssertEqual(child.nestingLevel(in: map), 1)
    }

    func testNestingLevelDepth3() {
        let root = RenderableComment(comment: MockComment.make(id: "root"))
        let depth1 = RenderableComment(comment: MockComment.make(id: "d1", parentId: "root"))
        let depth2 = RenderableComment(comment: MockComment.make(id: "d2", parentId: "d1"))
        let depth3 = RenderableComment(comment: MockComment.make(id: "d3", parentId: "d2"))
        let map: [String: RenderableComment] = [
            "root": root, "d1": depth1, "d2": depth2, "d3": depth3
        ]

        XCTAssertEqual(depth3.nestingLevel(in: map), 3)
    }

    func testNestingLevelOrphan() {
        let orphan = RenderableComment(comment: MockComment.make(id: "orphan", parentId: "missing_parent"))
        let map: [String: RenderableComment] = ["orphan": orphan]

        // Orphan with missing parent should return 0 (can't walk chain)
        XCTAssertEqual(orphan.nestingLevel(in: map), 0)
    }
}
