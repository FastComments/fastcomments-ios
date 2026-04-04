import XCTest
import CommonCrypto

/// Actor role — runs on Simulator B.
final class LiveEventUserB_UITests: UITestBase {

    override func setUpWithError() throws {
        SyncClient.currentRole = "userB"
        continueAfterFailure = false

        SyncClient.waitFor(role: "userA", round: "setup")
        let config = SyncClient.getData(round: "setup")

        testTenantId = config["tenantId"] as? String
        testTenantApiKey = config["apiKey"] as? String

        XCTAssertNotNil(testTenantId, "Should have tenantId from UserA")
    }

    override func tearDownWithError() throws {}

    func testLiveEvents_UserB() {
        let config = SyncClient.getData(round: "setup")
        let urlId = config["urlId"] as! String
        let ssoTokenB = config["ssoTokenB"] as! String
        let ssoTokenBAdmin = config["ssoTokenBAdmin"] as! String

        // --- Phase 1: Post a live comment ---
        SyncClient.waitFor(role: "userA", round: "phase1")

        launchApp(urlId: urlId, ssoToken: ssoTokenB)

        let commentText = "Live from B \(Int(Date().timeIntervalSince1970))"
        typeComment(commentText)
        XCTAssertTrue(app.staticTexts[commentText].waitForExistence(timeout: 10))

        SyncClient.postData(round: "phase1", data: ["text": commentText])
        SyncClient.signalReady(round: "phase1")

        // --- Phase 2: Vote on UserA's comment ---
        SyncClient.waitFor(role: "userA", round: "phase2")
        let phase2Data = SyncClient.getData(round: "phase2_setup")
        let voteCommentId = phase2Data["commentId"] as! String

        // UserA's comment should arrive via live event — no relaunch needed
        let voteUp = app.descendants(matching: .any)["vote-up-\(voteCommentId)"]
        XCTAssertTrue(voteUp.waitForExistence(timeout: 15), "Vote button should appear via live event")
        voteUp.tap()

        SyncClient.signalReady(round: "phase2")

        // --- Phase 3: Presence ---
        // UserB is already connected — just signal ready so UserA can check the indicator
        SyncClient.waitFor(role: "userA", round: "phase3")
        SyncClient.signalReady(round: "phase3")

        // --- Phase 4: Seed a comment then delete it ---
        SyncClient.waitFor(role: "userA", round: "phase4_ready")

        let deleteText = "Delete me live \(Int(Date().timeIntervalSince1970))"
        guard let deleteCommentId = seedComment(urlId: urlId, text: deleteText, ssoToken: ssoTokenB) else {
            SyncClient.signalReady(round: "phase4_deleted")
            XCTFail("Could not seed delete comment")
            return
        }

        SyncClient.postData(round: "phase4_posted", data: ["text": deleteText])
        SyncClient.signalReady(round: "phase4_posted")

        SyncClient.waitFor(role: "userA", round: "phase4_seen")

        // Comment should appear via live event — no relaunch needed
        XCTAssertTrue(app.staticTexts[deleteText].waitForExistence(timeout: 10))

        tapMenu(commentId: deleteCommentId, action: "Delete")
        let deleteBtn = app.alerts.buttons["Delete"]
        XCTAssertTrue(deleteBtn.waitForExistence(timeout: 5))
        deleteBtn.tap()

        pollUntil { !self.app.staticTexts[deleteText].exists }

        SyncClient.signalReady(round: "phase4_deleted")

        // --- Phase 5: Pin via menu (admin SSO) ---
        // Single relaunch to switch to admin identity — needed for pin/lock permissions
        SyncClient.waitFor(role: "userA", round: "phase5")
        let phase5Data = SyncClient.getData(round: "phase5_setup")
        let pinCommentId = phase5Data["commentId"] as! String

        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoTokenBAdmin)

        tapMenu(commentId: pinCommentId, action: "Pin")

        SyncClient.signalReady(round: "phase5")

        // --- Phase 6: Lock via menu (admin SSO) ---
        // Already running as admin — no relaunch needed
        SyncClient.waitFor(role: "userA", round: "phase6")
        let phase6Data = SyncClient.getData(round: "phase6_setup")
        let lockCommentId = phase6Data["commentId"] as! String

        // Lock target should appear via live event (seeded by UserA while we're connected)
        let lockMenuItem = app.staticTexts["Lock target from A"]
        XCTAssertTrue(lockMenuItem.waitForExistence(timeout: 10), "Lock target should appear via live event")

        tapMenu(commentId: lockCommentId, action: "Lock")

        SyncClient.signalReady(round: "phase6")
        SyncClient.waitFor(role: "userA", round: "done")
    }
}
