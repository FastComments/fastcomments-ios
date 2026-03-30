import XCTest
import FastCommentsSwift
@testable import FastCommentsUI

final class FeedStateTests: XCTestCase {

    func testInitDefaults() {
        let state = FeedState()

        XCTAssertNil(state.lastPostId)
        XCTAssertFalse(state.hasMore)
        XCTAssertEqual(state.pageSize, 10)
        XCTAssertEqual(state.newPostsCount, 0)
        XCTAssertTrue(state.feedPosts.isEmpty)
        XCTAssertTrue(state.myReacts.isEmpty)
        XCTAssertTrue(state.likeCounts.isEmpty)
    }

    func testCodableRoundtrip() throws {
        var state = FeedState()
        state.lastPostId = "post-123"
        state.hasMore = true
        state.pageSize = 20
        state.newPostsCount = 3
        state.myReacts = ["post-1": ["l": true]]
        state.likeCounts = ["post-1": 5, "post-2": 10]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(FeedState.self, from: data)

        XCTAssertEqual(decoded.lastPostId, "post-123")
        XCTAssertTrue(decoded.hasMore)
        XCTAssertEqual(decoded.pageSize, 20)
        XCTAssertEqual(decoded.newPostsCount, 3)
        XCTAssertEqual(decoded.myReacts["post-1"]?["l"], true)
        XCTAssertEqual(decoded.likeCounts["post-1"], 5)
        XCTAssertEqual(decoded.likeCounts["post-2"], 10)
    }

    func testMyReacts() {
        var state = FeedState()

        state.myReacts["post-1"] = ["l": true]
        state.myReacts["post-1"]?["heart"] = true

        XCTAssertEqual(state.myReacts["post-1"]?["l"], true)
        XCTAssertEqual(state.myReacts["post-1"]?["heart"], true)
        XCTAssertNil(state.myReacts["post-2"])
    }

    func testLikeCounts() {
        var state = FeedState()

        state.likeCounts["post-1"] = 5
        state.likeCounts["post-1"]! += 1

        XCTAssertEqual(state.likeCounts["post-1"], 6)
    }
}
