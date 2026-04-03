import XCTest

final class PaginationUITests: UITestBase {

    override var stableTenantEmail: String { "ios-pagination-ui@fctest.com" }

    func testCommentsRenderedInOrder() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        seedComment(urlId: urlId, text: "First comment", ssoToken: sso)
        seedComment(urlId: urlId, text: "Second comment", ssoToken: sso)
        seedComment(urlId: urlId, text: "Third comment", ssoToken: sso)

        launchApp(urlId: urlId, ssoToken: sso)

        let thirdComment = app.staticTexts["Third comment"]
        XCTAssertTrue(thirdComment.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Second comment"].exists)
        XCTAssertTrue(app.staticTexts["First comment"].exists)

        // Newest first: Third should be above First
        let thirdFrame = app.staticTexts["Third comment"].frame
        let firstFrame = app.staticTexts["First comment"].frame
        XCTAssertLessThan(thirdFrame.minY, firstFrame.minY, "Newest comment should be above oldest")
    }
}
