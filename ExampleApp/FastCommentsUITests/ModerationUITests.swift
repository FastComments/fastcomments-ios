import XCTest

final class ModerationUITests: UITestBase {

    func testPinShowsIcon() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        // Pin via admin API, then verify icon renders
        seedComment(urlId: urlId, text: "Pinned comment", ssoToken: sso)
        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }
        adminUpdateComment(commentId: commentId, params: ["isPinned": true])

        launchApp(urlId: urlId, ssoToken: sso)
        XCTAssertTrue(app.staticTexts["Pinned comment"].waitForExistence(timeout: 10))

        let pinIcon = app.descendants(matching: .any)["pin-icon-\(commentId)"]
        XCTAssertTrue(pinIcon.waitForExistence(timeout: 5), "Pin icon should be visible")
    }

    func testLockShowsIcon() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        // Lock via admin API, then verify icon renders
        seedComment(urlId: urlId, text: "Locked comment", ssoToken: sso)
        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }
        adminUpdateComment(commentId: commentId, params: ["isLocked": true])

        launchApp(urlId: urlId, ssoToken: sso)
        XCTAssertTrue(app.staticTexts["Locked comment"].waitForExistence(timeout: 10))

        let lockIcon = app.descendants(matching: .any)["lock-icon-\(commentId)"]
        XCTAssertTrue(lockIcon.waitForExistence(timeout: 5), "Lock icon should be visible")
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

        // Flag
        tapMenu(commentId: commentId, action: "Flag")

        // Wait for flag API to complete and isFlagged to update before re-opening menu
        let menu = app.buttons["menu-\(commentId)"]
        pollUntil(timeout: 5) {
            menu.tap()
            let hasUnflag = self.app.buttons["Unflag"].waitForExistence(timeout: 0.5)
            if !hasUnflag { self.app.tap() } // dismiss menu if Unflag not there yet
            return hasUnflag
        }

        let unflagButton = app.buttons["Unflag"]
        XCTAssertTrue(unflagButton.exists, "Menu should show 'Unflag' after flagging")
        // Dismiss menu
        app.tap()
    }

    // MARK: - Known Issues
    // These tests document bugs that need fixing. They are expected to fail.
    // Tracked at: https://github.com/FastComments/fastcomments-ios/issues

    func testBlockShowsBlockedText() throws {
        let urlId = makeUrlId()
        let userASSO = makeSecureSSOToken(userId: "user-a-block")
        let userBSSO = makeSecureSSOToken(userId: "user-b-block")

        seedComment(urlId: urlId, text: "Block my author", ssoToken: userASSO)
        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        launchApp(urlId: urlId, ssoToken: userBSSO)
        XCTAssertTrue(app.staticTexts["Block my author"].waitForExistence(timeout: 10))

        tapMenu(commentId: commentId, action: "Block User")

        XCTAssertTrue(
            app.staticTexts["Blocked User"].waitForExistence(timeout: 5),
            "Should show 'Blocked User' after blocking (known issue: UI may not re-render)"
        )
    }

    func testUnblockRestoresComment() throws {
        let urlId = makeUrlId()
        let userASSO = makeSecureSSOToken(userId: "user-a-unblock")
        let userBSSO = makeSecureSSOToken(userId: "user-b-unblock")

        seedComment(urlId: urlId, text: "Block then unblock", ssoToken: userASSO)
        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        launchApp(urlId: urlId, ssoToken: userBSSO)
        XCTAssertTrue(app.staticTexts["Block then unblock"].waitForExistence(timeout: 10))

        tapMenu(commentId: commentId, action: "Block User")
        XCTAssertTrue(app.staticTexts["Blocked User"].waitForExistence(timeout: 5), "Block should work")

        tapMenu(commentId: commentId, action: "Unblock User")

        XCTAssertTrue(
            app.staticTexts["Block then unblock"].waitForExistence(timeout: 5),
            "Original text should be restored after unblocking"
        )
    }
}
