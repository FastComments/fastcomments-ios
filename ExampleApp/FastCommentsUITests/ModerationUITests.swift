import XCTest
import FastCommentsSwift

final class ModerationUITests: UITestBase {

    override var stableTenantEmail: String { "ios-moderation-ui@fctest.com" }

    func testPinShowsIcon() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        // Pin via admin API, then verify icon renders
        seedComment(urlId: urlId, text: "Pinned comment", ssoToken: sso)
        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }
        adminUpdateComment(commentId: commentId, params: UpdatableCommentParams(isPinned: true))

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
        adminUpdateComment(commentId: commentId, params: UpdatableCommentParams(isLocked: true))

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

    // MARK: - Block / Unblock

    func testBlockShowsBlockedText() throws {
        let urlId = makeUrlId()
        let userASSO = makeSecureSSOToken(userId: "user-a-block")
        let userBSSO = makeSecureSSOToken(userId: "user-b-block")

        seedComment(urlId: urlId, text: "Block my author", ssoToken: userASSO)
        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        launchApp(urlId: urlId, ssoToken: userBSSO)
        XCTAssertTrue(app.staticTexts["Block my author"].waitForExistence(timeout: 10))

        tapMenu(commentId: commentId, action: "Block User")

        // Confirm the block alert
        let confirmButton = app.buttons["Block User"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Block confirmation alert should appear")
        confirmButton.tap()

        // Commenter name is inside a Button, so query via accessibility identifier
        let nameElement = app.descendants(matching: .any)["commenter-name-\(commentId)"]
        pollUntil(timeout: 5) {
            nameElement.label == "Blocked User"
        }
        XCTAssertEqual(nameElement.label, "Blocked User", "Should show 'Blocked User' after blocking")
    }

    func testUnblockRestoresComment() throws {
        let urlId = makeUrlId()
        let userASSO = makeSecureSSOToken(userId: "user-a-unblock")
        let userBSSO = makeSecureSSOToken(userId: "user-b-unblock")

        seedComment(urlId: urlId, text: "Block then unblock", ssoToken: userASSO)
        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        launchApp(urlId: urlId, ssoToken: userBSSO)
        XCTAssertTrue(app.staticTexts["Block then unblock"].waitForExistence(timeout: 10))

        let nameElement = app.descendants(matching: .any)["commenter-name-\(commentId)"]

        tapMenu(commentId: commentId, action: "Block User")

        // Confirm block
        let blockConfirm = app.buttons["Block User"]
        XCTAssertTrue(blockConfirm.waitForExistence(timeout: 5), "Block confirmation alert should appear")
        blockConfirm.tap()

        pollUntil(timeout: 5) {
            nameElement.label == "Blocked User"
        }
        XCTAssertEqual(nameElement.label, "Blocked User", "Block should work")

        tapMenu(commentId: commentId, action: "Unblock User")

        // Confirm unblock
        let unblockConfirm = app.buttons["Unblock User"]
        XCTAssertTrue(unblockConfirm.waitForExistence(timeout: 5), "Unblock confirmation alert should appear")
        unblockConfirm.tap()

        // After unblocking, the original comment text should be restored
        let commentText = app.descendants(matching: .any)["comment-text-\(commentId)"]
        pollUntil(timeout: 5) {
            commentText.label.contains("Block then unblock")
        }
        XCTAssertTrue(
            commentText.label.contains("Block then unblock"),
            "Original text should be restored after unblocking"
        )
    }
}
