import XCTest

final class VoteUITests: UITestBase {

    func testTapUpvote() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Vote on me")

        // Wait for comment to appear in UI (confirms it was posted)
        XCTAssertTrue(app.staticTexts["Vote on me"].waitForExistence(timeout: 10))

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            return // XCTFail already called by fetchLatestCommentId
        }

        let voteUp = app.buttons["vote-up-\(commentId)"]
        XCTAssertTrue(voteUp.waitForExistence(timeout: 5))
        voteUp.tap()

        let voteCount = app.staticTexts["vote-count-\(commentId)"]
        XCTAssertTrue(voteCount.waitForExistence(timeout: 5))
        // After upvote, count should show "+1"
        XCTAssertEqual(voteCount.label, "+1")
    }

    func testTapDownvote() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Downvote me")

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        let voteDown = app.buttons["vote-down-\(commentId)"]
        XCTAssertTrue(voteDown.waitForExistence(timeout: 5))
        voteDown.tap()

        let voteCount = app.staticTexts["vote-count-\(commentId)"]
        XCTAssertTrue(voteCount.waitForExistence(timeout: 5))
        XCTAssertEqual(voteCount.label, "-1")
    }

    func testToggleVote() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Toggle my vote")

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        let voteUp = app.buttons["vote-up-\(commentId)"]
        let voteDown = app.buttons["vote-down-\(commentId)"]
        let voteCount = app.staticTexts["vote-count-\(commentId)"]

        XCTAssertTrue(voteUp.waitForExistence(timeout: 5))

        // Upvote
        voteUp.tap()
        sleep(1)
        XCTAssertEqual(voteCount.label, "+1")

        // Switch to downvote
        voteDown.tap()
        sleep(1)
        XCTAssertEqual(voteCount.label, "-1")
    }
}
