import XCTest
import CommonCrypto

/// Observer role — runs on Simulator A.
final class LiveEventUserA_UITests: UITestBase {

    override var stableTenantEmail: String { "ios-live-events-ui@fctest.com" }

    override func setUpWithError() throws {
        SyncClient.currentRole = "userA"
        continueAfterFailure = true
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

        // Launch and wait for WebSocket (input bar means app is loaded)
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        _ = app.textViews["comment-input"].waitForExistence(timeout: 10)

        // --- Phase 1: Live comment ---
        SyncClient.signalReady(round: "phase1")
        SyncClient.waitFor(role: "userB", round: "phase1")

        let phase1Data = SyncClient.getData(round: "phase1")
        let commentText = phase1Data["text"] as? String ?? "?"

        XCTAssertTrue(
            app.staticTexts[commentText].waitForExistence(timeout: 15),
            "Live comment '\(commentText)' should appear on UserA"
        )

        // --- Phase 2: Live vote ---
        seedComment(urlId: urlId, text: "Vote target from A", ssoToken: ssoTokenA)
        guard let voteCommentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not get vote target comment ID")
            return
        }

        SyncClient.postData(round: "phase2_setup", data: ["commentId": voteCommentId])
        SyncClient.signalReady(round: "phase2")

        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        let voteCount = app.descendants(matching: .any)["vote-count-\(voteCommentId)"]
        XCTAssertTrue(voteCount.waitForExistence(timeout: 10), "Vote count element should exist")

        SyncClient.waitFor(role: "userB", round: "phase2")

        pollUntil(timeout: 10) { voteCount.label != "0" }
        XCTAssertNotEqual(voteCount.label, "0", "Vote count should change after UserB votes")

        // --- Phase 3: Presence ---
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

        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        XCTAssertTrue(app.staticTexts[deleteText].waitForExistence(timeout: 10), "Comment to delete should be visible")

        SyncClient.signalReady(round: "phase4_seen")
        SyncClient.waitFor(role: "userB", round: "phase4_deleted")

        pollUntil(timeout: 10) { !self.app.staticTexts[deleteText].exists }
        XCTAssertFalse(app.staticTexts[deleteText].exists, "Deleted comment should disappear from UserA")

        // --- Phase 5: Live pin ---
        seedComment(urlId: urlId, text: "Pin target from A", ssoToken: ssoTokenA)
        guard let pinCommentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not get pin target comment ID")
            return
        }

        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        XCTAssertTrue(app.staticTexts["Pin target from A"].waitForExistence(timeout: 10))

        SyncClient.postData(round: "phase5_setup", data: ["commentId": pinCommentId])
        SyncClient.signalReady(round: "phase5")
        SyncClient.waitFor(role: "userB", round: "phase5")

        let pinIcon = app.descendants(matching: .any)["pin-icon-\(pinCommentId)"]
        XCTAssertTrue(pinIcon.waitForExistence(timeout: 15), "Pin icon should appear after UserB pins")

        // --- Phase 6: Live lock ---
        seedComment(urlId: urlId, text: "Lock target from A", ssoToken: ssoTokenA)
        guard let lockCommentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not get lock target comment ID")
            SyncClient.signalReady(round: "done")
            return
        }

        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        XCTAssertTrue(app.staticTexts["Lock target from A"].waitForExistence(timeout: 10))

        SyncClient.postData(round: "phase6_setup", data: ["commentId": lockCommentId])
        SyncClient.signalReady(round: "phase6")
        SyncClient.waitFor(role: "userB", round: "phase6")

        let lockIcon = app.descendants(matching: .any)["lock-icon-\(lockCommentId)"]
        XCTAssertTrue(lockIcon.waitForExistence(timeout: 15), "Lock icon should appear after UserB locks")

        SyncClient.signalReady(round: "done")
    }
}
