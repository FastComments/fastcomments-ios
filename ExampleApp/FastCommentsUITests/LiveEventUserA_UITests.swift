import XCTest
import CommonCrypto

/// Observer role — runs on Simulator A.
final class LiveEventUserA_UITests: UITestBase {

    override var stableTenantEmail: String { "ios-live-events-ui@fctest.com" }

    override func setUpWithError() throws {
        SyncClient.currentRole = "userA"
        continueAfterFailure = false
        try super.setUpWithError()
    }

    func testLiveEvents_UserA() {
        let urlId = "live-\(Int(Date().timeIntervalSince1970))"
        let ssoTokenA = makeSecureSSOToken(userId: "userA-live")
        let ssoTokenB = makeSecureSSOToken(userId: "userB-live")
        let ssoTokenBAdmin = makeSecureSSOToken(userId: "userB-live", isAdmin: true)

        SyncClient.postData(round: "setup", data: [
            "tenantId": testTenantId!,
            "apiKey": testTenantApiKey!,
            "urlId": urlId,
            "ssoTokenB": ssoTokenB,
            "ssoTokenBAdmin": ssoTokenBAdmin,
        ])
        SyncClient.signalReady(round: "setup")

        // Single launch — all phases use the same app session and WebSocket connection
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        _ = app.textViews["comment-input"].waitForExistence(timeout: 10)

        // --- Phase 1: Live comment ---
        SyncClient.signalReady(round: "phase1")
        SyncClient.waitFor(role: "userB", round: "phase1")

        let phase1Data = SyncClient.getData(round: "phase1")
        let commentText = phase1Data["text"] as? String ?? "?"

        XCTAssertTrue(
            app.staticTexts[commentText].waitForExistence(timeout: 15),
            "Live comment '\(commentText)' should appear via WebSocket"
        )

        // --- Phase 2: Live vote ---
        guard let voteCommentId = seedComment(urlId: urlId, text: "Vote target from A", ssoToken: ssoTokenA) else {
            XCTFail("Could not seed vote target comment")
            return
        }

        // Wait for seeded comment to appear via live event
        XCTAssertTrue(
            app.staticTexts["Vote target from A"].waitForExistence(timeout: 10),
            "Seeded comment should appear via live event"
        )

        SyncClient.postData(round: "phase2_setup", data: ["commentId": voteCommentId])
        SyncClient.signalReady(round: "phase2")
        SyncClient.waitFor(role: "userB", round: "phase2")

        let voteCount = app.descendants(matching: .any)["vote-count-\(voteCommentId)"]
        pollUntil(timeout: 10) { voteCount.exists && voteCount.label != "0" }
        XCTAssertNotEqual(voteCount.label, "0", "Vote count should change via live WebSocket event")

        // --- Phase 3: Presence ---
        // UserB has been connected since Phase 1, so UserA should have already
        // received the p-u event. Just verify the indicator is visible.
        SyncClient.signalReady(round: "phase3")
        SyncClient.waitFor(role: "userB", round: "phase3")

        let onlineIndicator = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'online-'")
        ).firstMatch
        XCTAssertTrue(onlineIndicator.waitForExistence(timeout: 15), "Online indicator should appear when UserB joins")

        // --- Phase 4: Live delete ---
        SyncClient.signalReady(round: "phase4_ready")
        SyncClient.waitFor(role: "userB", round: "phase4_posted")

        let phase4Data = SyncClient.getData(round: "phase4_posted")
        let deleteText = phase4Data["text"] as? String ?? "?"

        // Comment should arrive via live event — no relaunch needed
        XCTAssertTrue(
            app.staticTexts[deleteText].waitForExistence(timeout: 10),
            "Delete target should appear via live event"
        )

        SyncClient.signalReady(round: "phase4_seen")
        SyncClient.waitFor(role: "userB", round: "phase4_deleted")

        pollUntil(timeout: 10) { !self.app.staticTexts[deleteText].exists }
        XCTAssertFalse(app.staticTexts[deleteText].exists, "Deleted comment should disappear via live WebSocket event")

        // --- Phase 5: Live pin ---
        guard let pinCommentId = seedComment(urlId: urlId, text: "Pin target from A", ssoToken: ssoTokenA) else {
            XCTFail("Could not seed pin target comment")
            return
        }

        XCTAssertTrue(
            app.staticTexts["Pin target from A"].waitForExistence(timeout: 10),
            "Pin target should appear via live event"
        )

        SyncClient.postData(round: "phase5_setup", data: ["commentId": pinCommentId])
        SyncClient.signalReady(round: "phase5")
        SyncClient.waitFor(role: "userB", round: "phase5")

        let pinIcon = app.descendants(matching: .any)["pin-icon-\(pinCommentId)"]
        XCTAssertTrue(pinIcon.waitForExistence(timeout: 15), "Pin icon should appear via live WebSocket event")

        // --- Phase 6: Live lock ---
        guard let lockCommentId = seedComment(urlId: urlId, text: "Lock target from A", ssoToken: ssoTokenA) else {
            SyncClient.signalReady(round: "done")
            XCTFail("Could not seed lock target comment")
            return
        }

        XCTAssertTrue(
            app.staticTexts["Lock target from A"].waitForExistence(timeout: 10),
            "Lock target should appear via live event"
        )

        SyncClient.postData(round: "phase6_setup", data: ["commentId": lockCommentId])
        SyncClient.signalReady(round: "phase6")
        SyncClient.waitFor(role: "userB", round: "phase6")

        let lockIcon = app.descendants(matching: .any)["lock-icon-\(lockCommentId)"]
        XCTAssertTrue(lockIcon.waitForExistence(timeout: 15), "Lock icon should appear via live WebSocket event")

        SyncClient.signalReady(round: "done")
    }
}
