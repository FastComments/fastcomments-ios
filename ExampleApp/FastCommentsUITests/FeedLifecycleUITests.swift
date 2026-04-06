import XCTest

final class FeedLifecycleUITests: UITestBase {

    override var stableTenantEmail: String { "ios-feed-lifecycle-ui@fctest.com" }

    func testFeedDisappearReappearDoesNotResetOrDuplicate() {
        let urlId = makeUrlId()
        let ssoToken = makeSecureSSOToken(userId: "feed-lifecycle-user")

        let seededTexts = (0..<5).map { index in
            "Lifecycle seed \(index) \(Int(Date().timeIntervalSince1970))"
        }
        for text in seededTexts {
            XCTAssertNotNil(seedFeedPost(urlId: urlId, text: text, ssoToken: ssoToken))
        }

        launchFeedLifecycleApp(urlId: urlId, ssoToken: ssoToken)

        let countLabel = waitForId("feed-lifecycle-count", timeout: 15)
        let lastIdLabel = waitForId("feed-lifecycle-last-id", timeout: 15)
        let lastTextLabel = waitForId("feed-lifecycle-last-text", timeout: 15)
        let toggleButton = waitForId("feed-lifecycle-toggle", timeout: 15)

        pollUntil(timeout: 15) {
            countLabel.label == "5"
        }
        XCTAssertEqual(countLabel.label, "5")

        let beforeLastId = lastIdLabel.label
        let beforeLastText = lastTextLabel.label
        XCTAssertNotEqual(beforeLastId, "none")
        XCTAssertEqual(beforeLastText, seededTexts.first)

        toggleButton.tap()
        XCTAssertTrue(app.staticTexts["feed-lifecycle-hidden"].waitForExistence(timeout: 10))

        toggleButton.tap()
        XCTAssertTrue(app.scrollViews["feed-lifecycle-view"].waitForExistence(timeout: 10) || app.otherElements["feed-lifecycle-view"].waitForExistence(timeout: 10))

        pollUntil(timeout: 10) {
            countLabel.label == "5" && lastIdLabel.label == beforeLastId && lastTextLabel.label == beforeLastText
        }

        XCTAssertEqual(countLabel.label, "5")
        XCTAssertEqual(lastIdLabel.label, beforeLastId)
        XCTAssertEqual(lastTextLabel.label, beforeLastText)
    }
}
