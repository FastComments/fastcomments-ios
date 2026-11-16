import XCTest
import FastCommentsSwift

/// Single-simulator tests for polls: building one in the composer, posting it, voting and changing the vote.
final class PollUITests: UITestBase {

    override var stableTenantEmail: String { "ios-polls-ui@fctest.com" }

    private var urlId = ""
    private var ssoToken = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        createCustomConfig(["pollCreation": 2])
        urlId = "polls-\(UUID().uuidString.prefix(8))"
        ssoToken = makeSecureSSOToken(userId: "poll-user")
        waitForPollCreationEnabled(urlId: urlId, ssoToken: ssoToken)
    }

    func testBuildPostAndVote() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"])
        attachScreenshot("poll-unvoted")

        waitForPollTotal(id, equals: "0 responses")
        XCTAssertFalse(app.buttons["poll-toolbar-button"].isSelected, "Posting should close the builder")
        XCTAssertFalse(app.descendants(matching: .any)["poll-builder-question"].exists)

        pollOption(id, 0).tap()

        waitForPollPercent(id, option: 0, equals: "100%")
        waitForPollPercent(id, option: 1, equals: "0%")
        waitForPollTotal(id, equals: "1 response")
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists)
        XCTAssertTrue(pollOption(id, 0).isSelected)
        XCTAssertFalse(pollOption(id, 1).isSelected)
        attachScreenshot("poll-voted")
    }

    func testChangeVote() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"])
        pollOption(id, 0).tap()
        waitForPollPercent(id, option: 0, equals: "100%")

        waitForId("poll-change-vote-\(id)").tap()
        waitForPollPercent(id, option: 0, equals: "")
        pollOption(id, 1).tap()

        waitForPollPercent(id, option: 1, equals: "100%")
        waitForPollPercent(id, option: 0, equals: "0%")
        waitForPollTotal(id, equals: "1 response")
    }

    func testVoteSurvivesRelaunch() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"])
        pollOption(id, 1).tap()
        waitForPollPercent(id, option: 1, equals: "100%")

        app.terminate()
        launchApp(urlId: urlId, ssoToken: ssoToken)

        waitForPollPercent(id, option: 1, equals: "100%")
        XCTAssertTrue(pollOption(id, 1).isSelected)
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists)
    }

    func testShowAndHideResultsBeforeVoting() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"])
        waitForPollPercent(id, option: 0, equals: "")

        let toggle = waitForId("poll-toggle-results-\(id)")
        XCTAssertEqual(toggle.label, "Show results")
        toggle.tap()
        waitForPollPercent(id, option: 0, equals: "0%")
        XCTAssertEqual(toggle.label, "Hide results")

        toggle.tap()
        waitForPollPercent(id, option: 0, equals: "")
    }

    func testHalfWrittenPollBlocksPost() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let pollButton = app.buttons["poll-toolbar-button"]
        XCTAssertTrue(pollButton.waitForExistence(timeout: 15))
        pollButton.tap()

        typeComment("No question yet")

        let error = waitForId("poll-builder-error")
        XCTAssertEqual(error.label, "Enter a question for your poll.")
        attachScreenshot("poll-builder-error")
        XCTAssertFalse(app.staticTexts["No question yet"].exists, "The comment should not have posted")

        // Typing clears the error, and one filled option still isn't enough.
        fillPollBuilder(question: "Lunch?", options: ["Tacos"])
        XCTAssertFalse(app.descendants(matching: .any)["poll-builder-error"].exists)
        app.buttons["comment-submit"].tap()
        XCTAssertEqual(waitForId("poll-builder-error").label, "Enter at least two options.")
    }

    func testAddAndRemoveOptions() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let pollButton = app.buttons["poll-toolbar-button"]
        XCTAssertTrue(pollButton.waitForExistence(timeout: 15))
        pollButton.tap()

        XCTAssertTrue(waitForId("poll-builder-option-1").exists)
        XCTAssertFalse(app.buttons["poll-builder-remove-option-0"].exists, "Two options is the minimum")

        waitForId("poll-builder-add-option").tap()
        XCTAssertTrue(waitForId("poll-builder-option-2").exists)
        waitForId("poll-builder-remove-option-2").tap()
        pollUntil { !self.app.descendants(matching: .any)["poll-builder-option-2"].exists }
        XCTAssertFalse(app.descendants(matching: .any)["poll-builder-option-2"].exists)

        waitForId("poll-builder-remove").tap()
        pollUntil { !self.app.descendants(matching: .any)["poll-builder-question"].exists }
        XCTAssertFalse(app.descendants(matching: .any)["poll-builder-question"].exists)
    }

    func testPublicPollShowsWhoVoted() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"],
            configure: {
                self.waitForId("poll-builder-duration-1").tap()
                self.waitForId("poll-builder-privacy").tap()
                let publicOption = self.app.buttons["Public"]
                XCTAssertTrue(publicOption.waitForExistence(timeout: 5))
                publicOption.tap()
            })

        XCTAssertTrue(waitForId("poll-closes-\(id)").label.hasPrefix("Poll closes"))
        XCTAssertFalse(app.buttons["poll-voters-\(id)"].exists, "Nobody has voted yet")

        pollOption(id, 1).tap()
        waitForPollPercent(id, option: 1, equals: "100%")

        waitForId("poll-voters-\(id)").tap()
        XCTAssertEqual(waitForId("poll-voters-count").label, "1 voter")
        XCTAssertTrue(app.staticTexts["Ramen"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("poll-voters")

        app.buttons["poll-voters-close"].tap()
        pollUntil { !self.app.buttons["poll-voters-close"].exists }
        XCTAssertFalse(app.buttons["poll-voters-close"].exists)
    }

    func testClosingThePollUpdatesTheCardLive() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"],
            configure: { self.waitForId("poll-builder-duration-1").tap() })
        pollOption(id, 0).tap()
        waitForPollPercent(id, option: 0, equals: "100%")
        XCTAssertTrue(waitForId("poll-closes-\(id)").label.hasPrefix("Poll closes"))

        adminClosePoll(commentId: id)

        let closes = app.staticTexts["poll-closes-\(id)"]
        pollUntil(timeout: 20) { closes.exists && closes.label == "Poll closed" }
        XCTAssertEqual(closes.label, "Poll closed")
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists, "The vote should survive the live update")
        XCTAssertFalse(app.buttons["poll-change-vote-\(id)"].exists)
        XCTAssertFalse(pollOption(id, 1).isEnabled)
        attachScreenshot("poll-closed")
    }

    /// A live update must leave the card working, not just looking right.
    func testVotingStillWorksAfterALiveEdit() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"])

        adminPatchPoll(commentId: id, CommentPollPatch(question: "Dinner plan?"))
        let question = app.staticTexts["poll-question-\(id)"]
        pollUntil(timeout: 20) { question.exists && question.label == "Dinner plan?" }
        XCTAssertEqual(question.label, "Dinner plan?")

        pollOption(id, 1).tap()

        waitForPollPercent(id, option: 1, equals: "100%")
        XCTAssertTrue(pollOption(id, 1).isSelected)
        XCTAssertTrue(waitForId("poll-saved-\(id)").exists)
    }

    func testOpeningTheBuilderFocusesTheQuestion() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let pollButton = app.buttons["poll-toolbar-button"]
        XCTAssertTrue(pollButton.waitForExistence(timeout: 15))
        pollButton.tap()

        // Nothing has been tapped, so the keyboard can only be up because the question took focus.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "The question should take focus")
        app.typeText("Lunch")
        let question = waitForId("poll-builder-question")
        XCTAssertEqual(question.value as? String, "Lunch")

        // Tapping the button again with the builder open comes back to the question.
        waitForId("poll-builder-option-0").tap()
        pollButton.tap()
        app.typeText(" plan")
        XCTAssertEqual(question.value as? String, "Lunch plan")
        XCTAssertEqual(waitForId("poll-builder-option-0").value as? String, "", "The text should not go to the option")
    }

    func testRightToLeftLayoutMirrors() {
        launchApp(
            urlId: urlId, ssoToken: ssoToken,
            extraArguments: ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"])
        pollOption(id, 0).tap()
        waitForPollPercent(id, option: 0, equals: "100%")

        let pill = waitForId("poll-saved-\(id)")
        let changeVote = waitForId("poll-change-vote-\(id)")
        XCTAssertGreaterThan(pill.frame.minX, changeVote.frame.minX, "The footer should flow from the right")
        attachScreenshot("poll-rtl")
    }

    func testAnonymousPollDoesNotOfferVoters() {
        launchApp(urlId: urlId, ssoToken: ssoToken)
        let id = buildAndPostPoll(
            urlId: urlId, comment: "Lunch vote", question: "Lunch plan?", options: ["Tacos", "Ramen"])
        pollOption(id, 0).tap()
        waitForPollPercent(id, option: 0, equals: "100%")
        XCTAssertFalse(app.buttons["poll-voters-\(id)"].exists)
    }
}
