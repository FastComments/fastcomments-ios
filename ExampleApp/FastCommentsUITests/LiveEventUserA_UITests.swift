import XCTest
import CommonCrypto

/// Observer role — runs on Simulator A.
/// Creates tenant, shares config, launches app, waits for UserB to act, asserts UI updates.
final class LiveEventUserA_UITests: UITestBase {

    override func setUpWithError() throws {
        SyncClient.currentRole = "userA"
        continueAfterFailure = true
        try super.setUpWithError()
    }

    func testLiveEvents_UserA() {
        let urlId = "live-\(Int(Date().timeIntervalSince1970))"
        let ssoTokenA = makeSecureSSOToken(userId: "userA-live")
        let ssoTokenB = makeSecureSSOToken(userId: "userB-live")

        // Share config with UserB
        SyncClient.postData(round: "setup", data: [
            "tenantId": testTenantId!,
            "apiKey": testTenantApiKey!,
            "urlId": urlId,
            "ssoTokenB": ssoTokenB,
        ])
        SyncClient.signalReady(round: "setup")

        // Launch app and wait for WebSocket
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        sleep(3)

        // --- Phase 1: Live comment ---
        SyncClient.signalReady(round: "phase1")
        SyncClient.waitFor(role: "userB", round: "phase1")

        let phase1Data = SyncClient.getData(round: "phase1")
        let commentText = phase1Data["text"] as? String ?? "?"

        XCTAssertTrue(
            app.staticTexts[commentText].waitForExistence(timeout: 15),
            "Live comment should appear on UserA's screen"
        )

        // --- Phase 2: Live vote ---
        // UserA seeds a comment for voting
        seedComment(urlId: urlId, text: "Vote target from A", ssoToken: ssoTokenA)
        guard let voteCommentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not get vote target comment ID")
            return
        }

        SyncClient.postData(round: "phase2_setup", data: ["commentId": voteCommentId])
        SyncClient.signalReady(round: "phase2")

        // Reload to see the seeded comment
        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        sleep(3)

        SyncClient.waitFor(role: "userB", round: "phase2")

        // Check vote count changed
        sleep(3)
        let voteCount = app.descendants(matching: .any)["vote-count-\(voteCommentId)"]
        if voteCount.exists {
            XCTAssertNotEqual(voteCount.label, "0", "Vote count should change")
        }

        SyncClient.signalReady(round: "done")
    }
}
