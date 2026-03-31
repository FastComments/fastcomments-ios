import XCTest

final class ModerationUITests: UITestBase {

    func testPinShowsIcon() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken(isAdmin: true)
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Pin me")

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        tapMenu(commentId: commentId, action: "Pin")
        sleep(2)

        // Pin icon should appear
        let pinIcon = app.images["pin-icon-\(commentId)"]
        XCTAssertTrue(pinIcon.waitForExistence(timeout: 5), "Pin icon should be visible")
    }

    func testLockShowsIcon() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken(isAdmin: true)
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Lock me")

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        tapMenu(commentId: commentId, action: "Lock")
        sleep(2)

        // Lock icon should appear
        let lockIcon = app.images["lock-icon-\(commentId)"]
        XCTAssertTrue(lockIcon.waitForExistence(timeout: 5), "Lock icon should be visible")
    }

    func testBlockShowsBlockedText() {
        let urlId = makeUrlId()
        let userASSO = makeSecureSSOToken(userId: "user-a")
        let userBSSO = makeSecureSSOToken(userId: "user-b")

        // User A seeds a comment via API
        seedComment(urlId: urlId, text: "Block my author", ssoToken: userASSO)

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        // Launch as User B
        launchApp(urlId: urlId, ssoToken: userBSSO)

        XCTAssertTrue(app.staticTexts["Block my author"].waitForExistence(timeout: 10))

        // User B blocks User A
        tapMenu(commentId: commentId, action: "Block User")
        sleep(2)

        // Should now show "Blocked User" and blocked message
        XCTAssertTrue(
            app.staticTexts["Blocked User"].waitForExistence(timeout: 5),
            "Should show 'Blocked User' after blocking"
        )
    }

    func testUnblockRestoresComment() {
        let urlId = makeUrlId()
        let userASSO = makeSecureSSOToken(userId: "user-a-unblock")
        let userBSSO = makeSecureSSOToken(userId: "user-b-unblock")

        seedComment(urlId: urlId, text: "Block then unblock", ssoToken: userASSO)

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        // Launch as User B
        launchApp(urlId: urlId, ssoToken: userBSSO)
        XCTAssertTrue(app.staticTexts["Block then unblock"].waitForExistence(timeout: 10))

        // Block
        tapMenu(commentId: commentId, action: "Block User")
        sleep(2)
        XCTAssertTrue(app.staticTexts["Blocked User"].waitForExistence(timeout: 5))

        // Unblock
        tapMenu(commentId: commentId, action: "Unblock User")
        sleep(2)

        // Original text should be restored
        XCTAssertTrue(
            app.staticTexts["Block then unblock"].waitForExistence(timeout: 5),
            "Original comment text should be restored after unblocking"
        )
    }

    func testFlagViaMenu() {
        let urlId = makeUrlId()
        let userASSO = makeSecureSSOToken(userId: "flag-author")
        let userBSSO = makeSecureSSOToken(userId: "flag-flagger")

        seedComment(urlId: urlId, text: "Flag this comment", ssoToken: userASSO)

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        // Launch as User B
        launchApp(urlId: urlId, ssoToken: userBSSO)
        XCTAssertTrue(app.staticTexts["Flag this comment"].waitForExistence(timeout: 10))

        // Flag — should not throw
        tapMenu(commentId: commentId, action: "Flag")
        sleep(2)

        // After flagging, menu should show "Unflag" instead
        let menu = app.buttons["menu-\(commentId)"]
        menu.tap()
        let unflagButton = app.buttons["Unflag"]
        XCTAssertTrue(unflagButton.waitForExistence(timeout: 5), "Menu should show 'Unflag' after flagging")
        // Dismiss menu
        app.tap()
    }
}
