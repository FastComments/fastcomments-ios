import XCTest
import CommonCrypto

/// Actor role (Phase 1) / Observer role (Phase 2) — runs on Simulator B.
final class FeedUserB_UITests: UITestBase {

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

    func testFeed_UserB() {
        let config = SyncClient.getData(round: "setup")
        let urlId = config["urlId"] as! String
        let ssoTokenB = config["ssoTokenB"] as! String

        // --- Phase 1: UserB creates a post via UI ---
        SyncClient.waitFor(role: "userA", round: "phase1")

        launchFeedApp(urlId: urlId, ssoToken: ssoTokenB)

        let openComposer = app.buttons["open-feed-post-composer"]
        XCTAssertTrue(openComposer.waitForExistence(timeout: 15), "Feed view should load")

        let postText = "Feed post from B \(Int(Date().timeIntervalSince1970))"
        openComposer.tap()

        let input = app.textFields["feed-post-content-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Feed composer should load")
        input.tap()
        input.typeText(postText)

        let submitBtn = app.buttons["feed-post-submit"]
        XCTAssertTrue(submitBtn.waitForExistence(timeout: 5))
        submitBtn.tap()

        // Wait for own post to appear locally before signaling UserA
        XCTAssertTrue(
            app.staticTexts[postText].waitForExistence(timeout: 10),
            "Own post should appear in feed after submission"
        )

        SyncClient.postData(round: "phase1", data: ["text": postText])
        SyncClient.signalReady(round: "phase1")

        // Clear any stale banner before Phase 2 so the next banner
        // is definitively from UserA's post, not our own
        let staleBanner = app.buttons["new-feed-posts-banner"]
        if staleBanner.waitForExistence(timeout: 5) {
            staleBanner.tap()
        }

        // --- Phase 2: UserB sees UserA's post via banner ---
        SyncClient.waitFor(role: "userA", round: "phase2")

        let phase2Data = SyncClient.getData(round: "phase2")
        let userAPostText = phase2Data["text"] as? String ?? "?"

        // Wait for "Show N New Posts" banner via WebSocket
        let banner = app.buttons["new-feed-posts-banner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 15),
            "New posts banner should appear when UserA posts"
        )

        // Tap banner to load new posts
        banner.tap()

        // Verify UserA's post text appears in the feed
        XCTAssertTrue(
            app.staticTexts[userAPostText].waitForExistence(timeout: 15),
            "UserA's post should appear in UserB's feed after tapping banner"
        )

        SyncClient.signalReady(round: "phase2_confirmed")
    }
}
