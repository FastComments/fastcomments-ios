import XCTest

/// Voter, on Simulator B. Sees User A's poll arrive live, watches the tally before voting, then votes and changes
/// the vote from the UI. Runs alongside `PollUserA_UITests` through `run_dual_sim_tests.py --suite polls`.
final class PollUserB_UITests: UITestBase {

    override func setUpWithError() throws {
        SyncClient.currentRole = "userB"
        continueAfterFailure = false

        SyncClient.waitFor(role: "userA", round: "setup", timeout: 240)
        let config = SyncClient.getData(round: "setup")
        testTenantId = config["tenantId"] as? String
        testTenantApiKey = config["apiKey"] as? String
        XCTAssertNotNil(testTenantId, "Should have tenantId from UserA")
    }

    override func tearDownWithError() throws {}

    func testLivePollVoting_UserB() {
        let config = SyncClient.getData(round: "setup")
        let urlId = config["urlId"] as! String
        let ssoTokenB = config["ssoTokenB"] as! String

        launchApp(urlId: urlId, ssoToken: ssoTokenB)
        XCTAssertTrue(app.textViews["comment-input"].waitForExistence(timeout: 15))
        SyncClient.signalReady(round: "b_ready")

        // --- A's poll arrives over the socket, with no reload, and results hidden until B votes ---
        SyncClient.waitFor(role: "userA", round: "poll_posted", timeout: 180)
        let id = SyncClient.getData(round: "poll_posted")["commentId"] as! String
        XCTAssertTrue(
            app.staticTexts["poll-question-\(id)"].waitForExistence(timeout: 20), "The new poll should arrive live")
        XCTAssertEqual(app.staticTexts["poll-question-\(id)"].label, "Lunch plan?")
        XCTAssertTrue(waitForId("poll-closes-\(id)").label.hasPrefix("Poll closes"))
        waitForPollPercent(id, option: 0, equals: "")
        waitForPollTotal(id, equals: "0 responses")
        attachScreenshot("b-1-poll-arrived")
        holdForRecording()
        SyncClient.signalReady(round: "b_saw_poll")

        // --- A votes: the count moves live, but B's results stay hidden because B hasn't voted ---
        SyncClient.waitFor(role: "userA", round: "a_voted")
        waitForPollTotal(id, equals: "1 response")
        XCTAssertEqual(
            pollOption(id, 0).value as? String, "", "Live tallies must not reveal results B hasn't asked for")
        attachScreenshot("b-2-count-moved-results-hidden")
        holdForRecording()

        // Peeking shows A's vote without it looking like B's own.
        waitForId("poll-toggle-results-\(id)").tap()
        waitForPollPercent(id, option: 0, equals: "100%")
        XCTAssertFalse(pollOption(id, 0).isSelected, "A's vote must not look like B's own")
        XCTAssertFalse(app.descendants(matching: .any)["poll-saved-\(id)"].exists)
        attachScreenshot("b-3-peeked-at-results")
        holdForRecording()

        // --- Vote for Ramen ---
        pollOption(id, 1).tap()
        waitForPollPercent(id, option: 1, equals: "50%")
        waitForPollPercent(id, option: 0, equals: "50%")
        waitForPollTotal(id, equals: "2 responses")
        XCTAssertTrue(pollOption(id, 1).isSelected)
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists)
        attachScreenshot("b-4-voted")
        SyncClient.signalReady(round: "b_voted")

        // --- Change to Tacos once A has looked at who voted ---
        SyncClient.waitFor(role: "userA", round: "a_checked_voters")
        waitForId("poll-change-vote-\(id)").tap()
        waitForPollPercent(id, option: 0, equals: "")
        holdForRecording()
        pollOption(id, 0).tap()
        waitForPollPercent(id, option: 0, equals: "100%")
        waitForPollTotal(id, equals: "2 responses")
        XCTAssertTrue(pollOption(id, 0).isSelected)
        attachScreenshot("b-5-changed-vote")
        SyncClient.signalReady(round: "b_changed")

        // --- The admin's reworded question arrives live, and B's vote stays ---
        SyncClient.waitFor(role: "userA", round: "a_edited")
        let question = app.staticTexts["poll-question-\(id)"]
        pollUntil(timeout: 20) { question.exists && question.label == "Lunch plan, final answer?" }
        XCTAssertEqual(question.label, "Lunch plan, final answer?")
        XCTAssertTrue(pollOption(id, 0).isSelected, "B's vote should survive the live edit")
        attachScreenshot("b-6-edited")
        holdForRecording()
        SyncClient.signalReady(round: "b_saw_edit")

        // --- The poll closes live, and B's vote stays ---
        SyncClient.waitFor(role: "userA", round: "a_closed")
        let closes = app.staticTexts["poll-closes-\(id)"]
        pollUntil(timeout: 20) { closes.exists && closes.label == "Poll closed" }
        XCTAssertEqual(closes.label, "Poll closed")
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists, "B's vote should survive the live update")
        XCTAssertFalse(app.buttons["poll-change-vote-\(id)"].exists)
        XCTAssertFalse(pollOption(id, 1).isEnabled)
        attachScreenshot("b-7-closed")
        holdForRecording()

        SyncClient.signalReady(round: "done")
    }
}
