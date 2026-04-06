import XCTest

final class FeedComposerUITests: UITestBase {

    override var stableTenantEmail: String { "ios-feed-composer-ui@fctest.com" }

    func testSubmitTextOnlyFeedPost() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchFeedComposerApp(urlId: urlId, ssoToken: sso)

        let input = app.textFields["feed-post-content-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Feed composer should load")

        let postText = "Text only post \(Int(Date().timeIntervalSince1970))"
        input.tap()
        input.typeText(postText)

        let submitButton = app.buttons["feed-post-submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5), "Submit button should appear")
        submitButton.tap()

        let createdPost = app.staticTexts["feed-created-post-content"]
        XCTAssertTrue(createdPost.waitForExistence(timeout: 15), "Created post marker should appear")
        XCTAssertEqual(createdPost.label, postText)
    }

    func testSubmitTextOnlyFeedPostFromFullFeedFlow() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchFullFeedApp(urlId: urlId, ssoToken: sso)

        let openComposer = app.buttons["open-feed-post-composer"]
        XCTAssertTrue(openComposer.waitForExistence(timeout: 15), "Feed screen should load")
        openComposer.tap()

        let input = app.textFields["feed-post-content-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Feed composer should load")

        let postText = "Full flow post \(Int(Date().timeIntervalSince1970))"
        input.tap()
        input.typeText(postText)

        let submitButton = app.buttons["feed-post-submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5), "Submit button should appear")
        submitButton.tap()

        XCTAssertTrue(app.staticTexts[postText].waitForExistence(timeout: 15), "Posted text should render in feed")
    }

    func testPullToRefreshTwiceAfterTextOnlyPostDoesNotCrash() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchFullFeedApp(urlId: urlId, ssoToken: sso)

        let openComposer = app.buttons["open-feed-post-composer"]
        XCTAssertTrue(openComposer.waitForExistence(timeout: 15), "Feed screen should load")
        openComposer.tap()

        let input = app.textFields["feed-post-content-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Feed composer should load")

        let postText = "Refresh test post \(Int(Date().timeIntervalSince1970))"
        input.tap()
        input.typeText(postText)

        let submitButton = app.buttons["feed-post-submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5), "Submit button should appear")
        submitButton.tap()

        XCTAssertTrue(app.staticTexts[postText].waitForExistence(timeout: 15), "Posted text should render in feed")

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10), "Feed scroll view should exist")

        scrollView.swipeDown()
        scrollView.swipeDown()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should remain running after refreshing twice")
        XCTAssertTrue(app.staticTexts[postText].waitForExistence(timeout: 15), "Posted text should still render after refreshing twice")
    }
}
