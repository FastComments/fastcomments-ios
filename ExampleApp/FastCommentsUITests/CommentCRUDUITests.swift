import XCTest

final class CommentCRUDUITests: UITestBase {

    func testEmptyPageShowsEmptyState() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        // Should show empty state since no comments exist
        let emptyText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'comment'")).firstMatch
        XCTAssertTrue(emptyText.waitForExistence(timeout: 10))
    }

    func testTypeAndSubmitComment() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        // Wait for load
        sleep(2)

        typeComment("Hello from UI test")

        // Verify comment appears
        let commentText = app.staticTexts["Hello from UI test"]
        XCTAssertTrue(commentText.waitForExistence(timeout: 10), "Posted comment should appear")
    }

    func testEditCommentViaMenu() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Original text")

        let originalText = app.staticTexts["Original text"]
        XCTAssertTrue(originalText.waitForExistence(timeout: 10))

        // Get comment ID to interact with menu
        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        tapMenu(commentId: commentId, action: "Edit")

        // Edit sheet should appear
        let editInput = app.textViews["edit-comment-input"]
        XCTAssertTrue(editInput.waitForExistence(timeout: 5), "Edit input should appear")

        // Clear and type new text
        editInput.tap()
        editInput.press(forDuration: 1.0)
        app.menuItems["Select All"].tap()
        editInput.typeText("Edited text")

        // Save
        let saveButton = app.buttons["edit-comment-save"]
        XCTAssertTrue(saveButton.exists)
        saveButton.tap()

        // Verify updated text appears
        let editedText = app.staticTexts["Edited text"]
        XCTAssertTrue(editedText.waitForExistence(timeout: 10), "Edited text should appear")
    }

    func testDeleteCommentViaMenu() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Delete me")

        let commentText = app.staticTexts["Delete me"]
        XCTAssertTrue(commentText.waitForExistence(timeout: 10))

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        tapMenu(commentId: commentId, action: "Delete")

        // Confirm delete in system alert
        let deleteButton = app.alerts.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        // Verify comment is gone
        sleep(2)
        XCTAssertFalse(app.staticTexts["Delete me"].exists, "Deleted comment should no longer appear")
    }

    func testPaginationLoadsMore() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        // Seed 35 comments via API (faster than typing 35 via UI)
        for i in 1...35 {
            seedComment(urlId: urlId, text: "Comment \(i)", ssoToken: sso)
        }

        launchApp(urlId: urlId, ssoToken: sso)

        // Wait for first page
        XCTAssertTrue(
            app.staticTexts["Comment 35"].waitForExistence(timeout: 15),
            "Newest comment should appear"
        )

        // Scroll to bottom
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<10 { scrollView.swipeUp() }

        // Find and tap Next
        let nextButton = app.buttons["pagination-next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        sleep(1)
        nextButton.tap()
        sleep(3)

        // Scroll down to find newly loaded comments
        scrollView.swipeUp()

        // Oldest comment should now exist somewhere
        XCTAssertTrue(
            app.staticTexts["Comment 1"].waitForExistence(timeout: 10),
            "Oldest comment should be reachable after pagination"
        )
    }
}
