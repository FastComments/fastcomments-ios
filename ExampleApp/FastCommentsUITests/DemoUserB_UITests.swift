import XCTest
import CommonCrypto

/// Bob (right simulator, actor role) for Segment 3: Live Real-Time Sync.
/// Runs on Simulator B. Uses admin SSO from start (no mid-segment relaunch).
/// Coordinates with DemoUserA via SyncClient.
final class DemoUserB_UITests: DemoTestBase {

    override func setUpWithError() throws {
        SyncClient.currentRole = "userB"
        continueAfterFailure = true

        // Wait for UserA to create the tenant and share config
        SyncClient.waitFor(role: "userA", round: "setup")
        let config = SyncClient.getData(round: "setup")

        testTenantId = config["tenantId"] as? String
        testTenantApiKey = config["apiKey"] as? String

        XCTAssertNotNil(testTenantId, "Should have tenantId from UserA")
    }

    override func tearDownWithError() throws {
        // UserA handles tenant cleanup
    }

    func testSegment3_LiveSync() {
        let config = SyncClient.getData(round: "setup")
        let urlId = config["urlId"] as! String
        let ssoTokenBAdmin = config["ssoTokenBAdmin"] as! String

        // Launch as Bob with admin SSO from the start (avoids mid-segment relaunch)
        launchApp(urlId: urlId, ssoToken: ssoTokenBAdmin)
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)

        // --- PHASE 1: Bob types and posts a comment ---
        SyncClient.waitFor(role: "userA", round: "phase1")
        pauseForViewer(0.3)

        let commentText = "Just deployed the latest build, looking great!"
        typeCommentSlowly(commentText)
        app.buttons["comment-submit"].tap()
        pollUntil(timeout: 10) { self.app.staticTexts[commentText].exists }

        SyncClient.postData(round: "phase1", data: ["text": commentText])
        SyncClient.signalReady(round: "phase1")

        // --- PHASE 2: Observe Alice's vote count change ---
        SyncClient.waitFor(role: "userA", round: "phase2")
        let phase2Data = SyncClient.getData(round: "phase2_setup")
        let voteCommentId = phase2Data["commentId"] as! String

        let voteCount = app.descendants(matching: .any)["vote-count-\(voteCommentId)"]
        if voteCount.waitForExistence(timeout: 10) {
            pollUntil(timeout: 10) { voteCount.label != "0" }
        }
        pauseForViewer(0.5)
        SyncClient.waitFor(role: "userA", round: "phase2_done")

        // --- PHASE 3: Bob pins via admin API ---
        SyncClient.waitFor(role: "userA", round: "phase3")
        adminUpdateComment(commentId: voteCommentId, params: ["isPinned": true])
        SyncClient.postData(round: "phase3", data: ["commentId": voteCommentId])
        SyncClient.signalReady(round: "phase3")
        pauseForViewer(0.5)

        // --- PHASE 4: Observe Alice's comment ---
        SyncClient.waitFor(role: "userA", round: "phase4")
        let phase4Data = SyncClient.getData(round: "phase4")
        let aliceText = phase4Data["text"] as? String ?? "?"
        pollUntil(timeout: 15) { self.app.staticTexts[aliceText].exists }
        pauseForViewer(1.0)

        SyncClient.waitFor(role: "userA", round: "done")
    }
}
