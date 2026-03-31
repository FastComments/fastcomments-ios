import XCTest
import CommonCrypto

/// Actor role — runs on Simulator B.
/// Reads tenant config from sync server, performs UI actions, signals UserA.
final class LiveEventUserB_UITests: UITestBase {

    override func setUpWithError() throws {
        // Do NOT call super — UserB does not create its own tenant.
        SyncClient.currentRole = "userB"
        continueAfterFailure = true

        // Wait for UserA to share config
        SyncClient.waitFor(role: "userA", round: "setup")
        let config = SyncClient.getData(round: "setup")

        testTenantId = config["tenantId"] as? String
        testTenantApiKey = config["apiKey"] as? String

        XCTAssertNotNil(testTenantId, "Should have tenantId from UserA")
    }

    override func tearDownWithError() throws {
        // Do NOT clean up — UserA owns the tenant.
    }

    func testLiveEvents_UserB() {
        let config = SyncClient.getData(round: "setup")
        let urlId = config["urlId"] as! String
        let ssoTokenB = config["ssoTokenB"] as! String

        // --- Phase 1: Post a live comment ---
        SyncClient.waitFor(role: "userA", round: "phase1")

        launchApp(urlId: urlId, ssoToken: ssoTokenB)
        sleep(2)

        let commentText = "Live from B \(Int(Date().timeIntervalSince1970))"
        typeComment(commentText)
        XCTAssertTrue(app.staticTexts[commentText].waitForExistence(timeout: 10))

        SyncClient.postData(round: "phase1", data: ["text": commentText])
        SyncClient.signalReady(round: "phase1")

        // --- Phase 2: Vote on UserA's comment ---
        SyncClient.waitFor(role: "userA", round: "phase2")
        let phase2Data = SyncClient.getData(round: "phase2_setup")
        let commentId = phase2Data["commentId"] as! String

        // Reload to see UserA's seeded comment
        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoTokenB)
        sleep(3)

        let voteUp = app.descendants(matching: .any)["vote-up-\(commentId)"]
        if voteUp.waitForExistence(timeout: 10) {
            voteUp.tap()
            sleep(1)
        } else {
            XCTFail("Vote button not found for \(commentId)")
        }

        SyncClient.signalReady(round: "phase2")
        SyncClient.waitFor(role: "userA", round: "done")
    }
}
