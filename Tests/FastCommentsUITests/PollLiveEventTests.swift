import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

/// How the SDK applies poll events, without a socket. `PollIntegrationTests` covers the same paths against the server.
@MainActor
final class PollLiveEventTests: XCTestCase {

    private func makeEvent(_ json: String) throws -> LiveEvent {
        try CodableHelper().jsonDecoder.decode(LiveEvent.self, from: Data(json.utf8))
    }

    private func makeSDK(myVotes: [String]? = nil) -> FastCommentsSDK {
        let sdk = FastCommentsSDK(config: FastCommentsWidgetConfig(tenantId: "t", urlId: "u"))
        var comment = MockComment.make(id: "c1")
        comment.poll = CommentPoll(
            question: "Q",
            options: [
                CommentPollOption(id: "a", label: "A", votes: 0),
                CommentPollOption(id: "b", label: "B", votes: 0),
            ],
            totalVotes: 0
        )
        comment.myPollVotes = myVotes
        sdk.commentsTree.build(comments: [comment])
        return sdk
    }

    private let pollUpdate = """
        {
            "type": "poll-update",
            "commentId": "c1",
            "broadcastId": "b1",
            "poll": {
                "options": [{"id": "a", "label": "A", "votes": 2}, {"id": "b", "label": "B", "votes": 1}],
                "totalVotes": 3,
                "closesAt": "2030-01-01T00:00:00.000Z"
            }
        }
        """

    func testPollUpdatePatchesTalliesAndCloseDateInPlace() throws {
        let sdk = makeSDK()
        let renderable = try XCTUnwrap(sdk.commentsTree.commentsById["c1"])

        sdk.handleLiveEvent(try makeEvent(pollUpdate))

        XCTAssertTrue(sdk.commentsTree.commentsById["c1"] === renderable, "A tally change shouldn't rebuild the row")
        XCTAssertEqual(renderable.comment.poll?.totalVotes, 3)
        XCTAssertEqual(renderable.comment.poll?.options.map(\.votes), [2, 1])
        XCTAssertNotNil(renderable.comment.poll?.closesAt)
        XCTAssertEqual(renderable.comment.poll?.question, "Q")
    }

    func testPollUpdatePublishesAChange() throws {
        let sdk = makeSDK()
        let renderable = try XCTUnwrap(sdk.commentsTree.commentsById["c1"])
        var changes = 0
        let subscription = renderable.objectWillChange.sink { changes += 1 }

        sdk.handleLiveEvent(try makeEvent(pollUpdate))

        XCTAssertEqual(changes, 1)
        subscription.cancel()
    }

    func testOwnPollUpdateIsSkipped() throws {
        let sdk = makeSDK()
        sdk.broadcastIdsSent.insert("b1")

        sdk.handleLiveEvent(try makeEvent(pollUpdate))

        XCTAssertEqual(sdk.commentsTree.commentsById["c1"]?.comment.poll?.totalVotes, 0)
    }

    func testPollUpdateForUnknownCommentIsIgnored() throws {
        let sdk = makeSDK()
        let event = try makeEvent(pollUpdate.replacingOccurrences(of: "\"c1\"", with: "\"other\""))

        sdk.handleLiveEvent(event)

        XCTAssertEqual(sdk.commentsTree.commentsById["c1"]?.comment.poll?.totalVotes, 0)
    }

    func testUpdatedCommentKeepsViewerStateAndTakesThePoll() throws {
        let sdk = makeSDK(myVotes: ["a"])
        let before = try XCTUnwrap(sdk.commentsTree.commentsById["c1"])
        before.pollShowResults = false
        before.pollError = "Some error"

        sdk.handleLiveEvent(
            try makeEvent(
                """
                {
                    "type": "updated-comment",
                    "comment": {
                        "_id": "c1",
                        "commenterName": "Someone",
                        "commentHTML": "<p>Edited</p>",
                        "isPinned": true,
                        "poll": {
                            "question": "New question",
                            "options": [{"id": "a", "label": "A", "votes": 5}],
                            "totalVotes": 5
                        }
                    }
                }
                """))

        let after = try XCTUnwrap(sdk.commentsTree.commentsById["c1"])
        XCTAssertEqual(after.comment.poll?.question, "New question")
        XCTAssertEqual(after.comment.myPollVotes, ["a"], "Live events never carry the viewer's own vote")
        XCTAssertEqual(after.pollShowResults, false)
        XCTAssertEqual(after.pollError, "Some error")
    }

    func testUpdatedCommentUpdatesTheSameObject() throws {
        let sdk = makeSDK()
        let before = try XCTUnwrap(sdk.commentsTree.commentsById["c1"])
        var changes = 0
        let subscription = before.objectWillChange.sink { changes += 1 }

        sdk.handleLiveEvent(
            try makeEvent(#"{"type": "updated-comment", "comment": {"_id": "c1", "commentHTML": "Edited"}}"#))

        XCTAssertTrue(sdk.commentsTree.commentsById["c1"] === before, "Views observing the comment must stay attached")
        XCTAssertEqual(before.comment.commentHTML, "Edited")
        XCTAssertEqual(changes, 1)
        subscription.cancel()
    }

    func testUpdatedCommentKeepsVotesRepliesAndDate() throws {
        let sdk = makeSDK()
        let before = try XCTUnwrap(sdk.commentsTree.commentsById["c1"])
        before.comment.isVotedUp = true
        before.comment.myVoteId = "vote-1"
        before.comment.childCount = 3

        sdk.handleLiveEvent(
            try makeEvent(
                """
                {
                    "type": "updated-comment",
                    "comment": {"_id": "c1", "commentHTML": "x", "isPinned": true, "date": "2026-01-02T03:04:05.678Z"}
                }
                """))

        let after = try XCTUnwrap(sdk.commentsTree.commentsById["c1"]?.comment)
        XCTAssertEqual(after.isPinned, true)
        XCTAssertEqual(after.isVotedUp, true)
        XCTAssertEqual(after.myVoteId, "vote-1")
        XCTAssertEqual(after.childCount, 3)
        XCTAssertNotNil(after.date, "The server's fractional seconds should parse")
    }

    func testLiveDatesParseWithAndWithoutFractionalSeconds() {
        XCTAssertEqual(
            LiveEventHandler.parseDate("2026-01-02T03:04:05.500Z")?.timeIntervalSince1970, 1_767_323_045.5)
        XCTAssertEqual(LiveEventHandler.parseDate("2026-01-02T03:04:05Z")?.timeIntervalSince1970, 1_767_323_045)
        XCTAssertNil(LiveEventHandler.parseDate("not a date"))
    }

    func testUpdatedCommentCanRemoveThePoll() throws {
        let sdk = makeSDK()

        sdk.handleLiveEvent(
            try makeEvent(
                #"{"type": "updated-comment", "comment": {"_id": "c1", "commentHTML": "x", "poll": null}}"#))

        XCTAssertNil(sdk.commentsTree.commentsById["c1"]?.comment.poll)
    }

    func testNewCommentCarriesItsPoll() throws {
        let sdk = makeSDK()

        sdk.handleLiveEvent(
            try makeEvent(
                """
                {
                    "type": "new-comment",
                    "comment": {
                        "_id": "c2",
                        "commenterName": "Someone",
                        "commentHTML": "<p>Vote</p>",
                        "poll": {
                            "question": "Live?",
                            "options": [{"id": "a", "label": "A", "votes": 0}],
                            "totalVotes": 0,
                            "closesAt": "2030-01-01T00:00:00.000Z"
                        }
                    }
                }
                """))

        XCTAssertEqual(sdk.commentsTree.commentsById["c2"]?.comment.poll?.question, "Live?")
    }

    func testTappingAfterTheCloseDateRedrawsTheCard() async throws {
        let sdk = makeSDK()
        let renderable = try XCTUnwrap(sdk.commentsTree.commentsById["c1"])
        renderable.comment.poll?.closesAt = Date().addingTimeInterval(-1)
        var changes = 0
        let subscription = renderable.objectWillChange.sink { changes += 1 }

        await sdk.selectPollOption(commentId: "c1", optionId: "a")

        XCTAssertEqual(changes, 1)
        XCTAssertFalse(renderable.pollSaving)
        XCTAssertNil(renderable.pollError)
        subscription.cancel()
    }

    func testLiveChatNeverOffersPolls() {
        let sdk = makeSDK()
        sdk.commentsTree.liveChatStyle = true
        XCTAssertFalse(sdk.canCreatePoll)
    }
}
