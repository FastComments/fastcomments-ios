import XCTest

final class CommentCRUDUITests: UITestBase {

    func testEmptyPageShowsEmptyState() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        let emptyText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'comment'")).firstMatch
        XCTAssertTrue(emptyText.waitForExistence(timeout: 10))
    }

    func testTypeAndSubmitComment() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        typeComment("Hello from UI test")

        XCTAssertTrue(
            app.staticTexts["Hello from UI test"].waitForExistence(timeout: 10),
            "Posted comment should appear"
        )
    }

    func testEditCommentViaMenu() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        typeComment("Original text")
        XCTAssertTrue(app.staticTexts["Original text"].waitForExistence(timeout: 10))

        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        tapMenu(commentId: commentId, action: "Edit")

        let editInput = app.textViews["edit-comment-input"]
        XCTAssertTrue(editInput.waitForExistence(timeout: 5))

        editInput.tap()
        editInput.press(forDuration: 1.0)
        app.menuItems["Select All"].tap()
        editInput.typeText("Edited text")

        app.buttons["edit-comment-save"].tap()

        XCTAssertTrue(
            app.staticTexts["Edited text"].waitForExistence(timeout: 10),
            "Edited text should appear"
        )
    }

    func testDeleteCommentViaMenu() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        typeComment("Delete me")
        XCTAssertTrue(app.staticTexts["Delete me"].waitForExistence(timeout: 10))

        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        tapMenu(commentId: commentId, action: "Delete")

        let deleteButton = app.alerts.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        // Poll until comment disappears
        pollUntil(timeout: 5) { !self.app.staticTexts["Delete me"].exists }
        XCTAssertFalse(app.staticTexts["Delete me"].exists, "Deleted comment should no longer appear")
    }

    func testPaginationLoadsMore() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        for i in 1...35 {
            seedComment(urlId: urlId, text: "Comment \(i)", ssoToken: sso)
        }

        launchApp(urlId: urlId, ssoToken: sso)
        XCTAssertTrue(app.staticTexts["Comment 35"].waitForExistence(timeout: 15))

        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<10 { scrollView.swipeUp() }

        let nextButton = app.buttons["pagination-next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        // Poll for oldest comment to become reachable
        scrollView.swipeUp()
        XCTAssertTrue(
            app.staticTexts["Comment 1"].waitForExistence(timeout: 10),
            "Oldest comment should be reachable after pagination"
        )
    }
}
