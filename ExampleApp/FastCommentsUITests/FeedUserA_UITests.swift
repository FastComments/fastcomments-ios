import XCTest
import CommonCrypto

/// Observer role (Phase 1) / Actor role (Phase 2) — runs on Simulator A.
final class FeedUserA_UITests: UITestBase {

    override var stableTenantEmail: String { "ios-feed-ui@fctest.com" }

    override func setUpWithError() throws {
        SyncClient.currentRole = "userA"
        continueAfterFailure = false
        try super.setUpWithError()
    }

    func testFeed_UserA() {
        let urlId = "feed-\(Int(Date().timeIntervalSince1970))"
        let ssoTokenA = makeSecureSSOToken(userId: "userA-feed")
        let ssoTokenB = makeSecureSSOToken(userId: "userB-feed")

        SyncClient.postData(round: "setup", data: [
            "tenantId": testTenantId!,
            "apiKey": testTenantApiKey!,
            "urlId": urlId,
            "ssoTokenB": ssoTokenB,
        ])
        SyncClient.signalReady(round: "setup")

        // Single launch — both phases use the same app session and WebSocket connection.
        // Must load and establish WebSocket BEFORE signaling phase1 ready.
        launchFeedApp(urlId: urlId, ssoToken: ssoTokenA)

        // Wait for feed to be ready (input field means the view loaded and sdk.load() started)
        let input = app.textFields["feed-post-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Feed view should load")

        // --- Phase 1: UserB posts via API, UserA sees banner and taps it ---
        SyncClient.signalReady(round: "phase1")
        SyncClient.waitFor(role: "userB", round: "phase1")

        let phase1Data = SyncClient.getData(round: "phase1")
        let postTextB = phase1Data["text"] as? String ?? "?"

        // Wait for "Show N New Posts" banner via WebSocket
        let banner = app.buttons["new-feed-posts-banner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 15),
            "New posts banner should appear when UserB posts"
        )

        // Tap banner to load new posts
        banner.tap()

        // Verify UserB's post text appears in the feed
        XCTAssertTrue(
            app.staticTexts[postTextB].waitForExistence(timeout: 15),
            "UserB's post should appear after tapping new posts banner"
        )

        // --- Phase 2: UserA creates post via UI, UserB sees it ---
        let myPostText = "Feed post from A \(Int(Date().timeIntervalSince1970))"
        input.tap()
        input.typeText(myPostText)

        let submitBtn = app.buttons["feed-post-submit"]
        XCTAssertTrue(submitBtn.waitForExistence(timeout: 5))
        submitBtn.tap()

        // Wait for own post to appear locally before signaling UserB
        XCTAssertTrue(
            app.staticTexts[myPostText].waitForExistence(timeout: 10),
            "Own post should appear in feed after submission"
        )

        SyncClient.postData(round: "phase2", data: ["text": myPostText])
        SyncClient.signalReady(round: "phase2")
        SyncClient.waitFor(role: "userB", round: "phase2_confirmed")
    }
}
