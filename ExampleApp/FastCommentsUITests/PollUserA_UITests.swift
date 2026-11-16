import XCTest
import FastCommentsSwift

/// Poll author, on Simulator A. Builds a public poll, votes, and watches User B's votes arrive without touching
/// anything. Runs alongside `PollUserB_UITests` through `run_dual_sim_tests.py --suite polls`.
final class PollUserA_UITests: UITestBase {

    override var stableTenantEmail: String { "ios-polls-live-ui@fctest.com" }

    override func setUpWithError() throws {
        SyncClient.currentRole = "userA"
        continueAfterFailure = false
        try super.setUpWithError()
    }

    func testLivePollVoting_UserA() {
        let urlId = "live-polls-\(UUID().uuidString.prefix(8))"
        let ssoTokenA = makeSecureSSOToken(userId: "userA-polls", username: "Alex")
        createCustomConfig(["pollCreation": 2])
        waitForPollCreationEnabled(urlId: urlId, ssoToken: ssoTokenA)

        SyncClient.postData(
            round: "setup",
            data: [
                "tenantId": testTenantId!,
                "apiKey": testTenantApiKey!,
                "urlId": urlId,
                "ssoTokenB": makeSecureSSOToken(userId: "userB-polls", username: "Blake"),
            ])
        SyncClient.signalReady(round: "setup")
        SyncClient.waitFor(role: "userB", round: "b_ready", timeout: 180)

        launchApp(urlId: urlId, ssoToken: ssoTokenA)

        // A public poll that closes in a day: the close date is what a plain JSON decoder would drop live events over,
        // and public is what lets each user see who the other voted for.
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"],
            configure: {
                self.waitForId("poll-builder-duration-1").tap()
                self.waitForId("poll-builder-privacy").tap()
                let publicOption = self.app.buttons["Public"]
                XCTAssertTrue(publicOption.waitForExistence(timeout: 5))
                publicOption.tap()
                self.holdForRecording()
            })
        attachScreenshot("a-1-posted")
        holdForRecording()
        SyncClient.postData(round: "poll_posted", data: ["commentId": id])
        SyncClient.signalReady(round: "poll_posted")

        // --- A votes Tacos first, while B hasn't voted ---
        SyncClient.waitFor(role: "userB", round: "b_saw_poll")
        pollOption(id, 0).tap()
        waitForPollPercent(id, option: 0, equals: "100%")
        waitForPollTotal(id, equals: "1 response")
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists)
        attachScreenshot("a-2-voted")
        SyncClient.signalReady(round: "a_voted")

        // --- B votes Ramen: the bars move here with no interaction, and A's own vote stays marked ---
        SyncClient.waitFor(role: "userB", round: "b_voted")
        waitForPollPercent(id, option: 0, equals: "50%")
        waitForPollPercent(id, option: 1, equals: "50%")
        waitForPollTotal(id, equals: "2 responses")
        XCTAssertTrue(pollOption(id, 0).isSelected, "A's own vote should stay marked through live updates")
        XCTAssertFalse(pollOption(id, 1).isSelected, "B's vote must not look like A's own")
        attachScreenshot("a-3-after-b-voted")
        holdForRecording()

        // --- Who voted lists B's vote, which only exists on the other device ---
        waitForId("poll-voters-\(id)").tap()
        XCTAssertEqual(waitForId("poll-voters-count").label, "2 voters")
        let blakeRow = app.staticTexts["Blake"]
        XCTAssertTrue(blakeRow.waitForExistence(timeout: 10), "B should be listed as a voter")
        XCTAssertTrue(app.staticTexts["Ramen"].firstMatch.exists)
        attachScreenshot("a-4-who-voted")
        holdForRecording()
        app.buttons["poll-voters-close"].tap()
        pollUntil { !self.app.buttons["poll-voters-close"].exists }
        SyncClient.signalReady(round: "a_checked_voters")

        // --- B changes to Tacos: the total stays, the split moves ---
        SyncClient.waitFor(role: "userB", round: "b_changed")
        waitForPollPercent(id, option: 0, equals: "100%")
        waitForPollPercent(id, option: 1, equals: "0%")
        waitForPollTotal(id, equals: "2 responses")
        XCTAssertTrue(pollOption(id, 0).isSelected)
        attachScreenshot("a-5-after-b-changed")
        holdForRecording()

        // --- An admin rewords the question through the API: both cards pick it up live, votes intact ---
        adminPatchPoll(commentId: id, CommentPollPatch(question: "Lunch plan, final answer?"))
        SyncClient.signalReady(round: "a_edited")
        let question = app.staticTexts["poll-question-\(id)"]
        pollUntil(timeout: 20) { question.exists && question.label == "Lunch plan, final answer?" }
        XCTAssertEqual(question.label, "Lunch plan, final answer?")
        XCTAssertTrue(pollOption(id, 0).isSelected, "A's vote should survive the live edit")
        waitForPollPercent(id, option: 0, equals: "100%")
        attachScreenshot("a-6-edited")
        holdForRecording()

        // --- The poll closes through the API: both cards close live and keep their votes ---
        SyncClient.waitFor(role: "userB", round: "b_saw_edit")
        adminClosePoll(commentId: id)
        SyncClient.signalReady(round: "a_closed")
        let closes = app.staticTexts["poll-closes-\(id)"]
        pollUntil(timeout: 20) { closes.exists && closes.label == "Poll closed" }
        XCTAssertEqual(closes.label, "Poll closed")
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists, "A's vote should survive the live update")
        XCTAssertFalse(app.buttons["poll-change-vote-\(id)"].exists)
        XCTAssertFalse(pollOption(id, 1).isEnabled)
        attachScreenshot("a-7-closed")
        holdForRecording()

        SyncClient.waitFor(role: "userB", round: "done")
    }
}
