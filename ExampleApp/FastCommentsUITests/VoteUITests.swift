import XCTest

final class VoteUITests: UITestBase {

    override var stableTenantEmail: String { "ios-vote-ui@fctest.com" }

    func testTapUpvote() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        typeComment("Vote on me")
        XCTAssertTrue(app.staticTexts["Vote on me"].waitForExistence(timeout: 10))

        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        let voteUp = app.buttons["vote-up-\(commentId)"]
        XCTAssertTrue(voteUp.waitForExistence(timeout: 5))
        voteUp.tap()

        let voteCount = app.staticTexts["vote-count-\(commentId)"]
        XCTAssertTrue(voteCount.waitForExistence(timeout: 5))
        pollUntil { voteCount.label == "+1" }
        XCTAssertEqual(voteCount.label, "+1")
    }

    func testTapDownvote() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        typeComment("Downvote me")
        XCTAssertTrue(app.staticTexts["Downvote me"].waitForExistence(timeout: 10))

        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        let voteDown = app.buttons["vote-down-\(commentId)"]
        XCTAssertTrue(voteDown.waitForExistence(timeout: 5))
        voteDown.tap()

        let voteCount = app.staticTexts["vote-count-\(commentId)"]
        XCTAssertTrue(voteCount.waitForExistence(timeout: 5))
        pollUntil { voteCount.label == "-1" }
        XCTAssertEqual(voteCount.label, "-1")
    }

    func testToggleVote() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        typeComment("Toggle my vote")
        XCTAssertTrue(app.staticTexts["Toggle my vote"].waitForExistence(timeout: 10))

        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        let voteUp = app.buttons["vote-up-\(commentId)"]
        let voteDown = app.buttons["vote-down-\(commentId)"]
        let voteCount = app.staticTexts["vote-count-\(commentId)"]

        XCTAssertTrue(voteUp.waitForExistence(timeout: 5))

        voteUp.tap()
        pollUntil { voteCount.label == "+1" }
        XCTAssertEqual(voteCount.label, "+1")

        voteDown.tap()
        pollUntil { voteCount.label == "-1" }
        XCTAssertEqual(voteCount.label, "-1")
    }
}
