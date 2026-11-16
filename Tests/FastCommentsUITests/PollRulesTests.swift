import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

final class PollRulesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePoll(
        closesAt: Date? = nil, privacy: PollPrivacy? = nil, requireVote: Bool? = nil
    ) -> CommentPoll {
        CommentPoll(
            question: "Q",
            options: [
                CommentPollOption(id: "a", label: "A", votes: 1),
                CommentPollOption(id: "b", label: "B", votes: 2),
            ],
            totalVotes: 3,
            closesAt: closesAt,
            privacy: privacy,
            requireVoteToSeeResults: requireVote
        )
    }

    private func makeComment(poll: CommentPoll, myVotes: [String]? = nil) -> PublicComment {
        var comment = MockComment.make()
        comment.poll = poll
        comment.myPollVotes = myVotes
        return comment
    }

    func testIsClosedAtExactlyTheCloseDate() {
        XCTAssertFalse(PollRules.isClosed(makePoll(), now: now))
        XCTAssertFalse(PollRules.isClosed(makePoll(closesAt: now.addingTimeInterval(1)), now: now))
        XCTAssertTrue(PollRules.isClosed(makePoll(closesAt: now), now: now))
    }

    func testPercentRoundsLikeTheWeb() {
        XCTAssertEqual(PollRules.percent(votes: 1, total: 3), 33)
        XCTAssertEqual(PollRules.percent(votes: 2, total: 3), 67)
        XCTAssertEqual(PollRules.percent(votes: 1, total: 8), 13)
        XCTAssertEqual(PollRules.percent(votes: 0, total: 0), 0)
    }

    func testResultsHiddenUntilVotedByDefault() {
        let comment = makeComment(poll: makePoll())
        XCTAssertFalse(PollRules.isShowingResults(comment, showResultsOverride: nil, now: now))
        XCTAssertTrue(PollRules.isShowingResults(comment, showResultsOverride: true, now: now))
    }

    func testResultsShownOnceVoted() {
        let comment = makeComment(poll: makePoll(), myVotes: ["a"])
        XCTAssertTrue(PollRules.isShowingResults(comment, showResultsOverride: nil, now: now))
        // "Change vote" hides them again.
        XCTAssertFalse(PollRules.isShowingResults(comment, showResultsOverride: false, now: now))
    }

    func testLockedResultsIgnoreTheOverride() {
        let comment = makeComment(poll: makePoll(requireVote: true))
        XCTAssertTrue(PollRules.resultsLocked(comment, now: now))
        XCTAssertFalse(PollRules.isShowingResults(comment, showResultsOverride: true, now: now))
    }

    func testVotingUnlocksResults() {
        let comment = makeComment(poll: makePoll(requireVote: true), myVotes: ["a"])
        XCTAssertFalse(PollRules.resultsLocked(comment, now: now))
        XCTAssertTrue(PollRules.isShowingResults(comment, showResultsOverride: nil, now: now))
    }

    func testClosedPollAlwaysShowsResults() {
        let poll = makePoll(closesAt: now.addingTimeInterval(-1), requireVote: true)
        let comment = makeComment(poll: poll)
        XCTAssertFalse(PollRules.resultsLocked(comment, now: now))
        XCTAssertTrue(PollRules.isShowingResults(comment, showResultsOverride: false, now: now))
    }

    func testCanVote() {
        let open = makePoll()
        let loggedIn = UserSessionInfo(id: "u", isAnonSession: false)
        let anon = UserSessionInfo(id: "u", isAnonSession: true)
        let anyone = CustomConfigParameters(pollVoting: ._1)
        let loggedInOnly = CustomConfigParameters(pollVoting: ._0)

        XCTAssertTrue(PollRules.canVote(config: loggedInOnly, currentUser: loggedIn, poll: open, now: now))
        XCTAssertFalse(PollRules.canVote(config: loggedInOnly, currentUser: anon, poll: open, now: now))
        XCTAssertFalse(PollRules.canVote(config: loggedInOnly, currentUser: nil, poll: open, now: now))
        XCTAssertFalse(PollRules.canVote(config: nil, currentUser: nil, poll: open, now: now))
        XCTAssertTrue(PollRules.canVote(config: anyone, currentUser: anon, poll: open, now: now))
        XCTAssertTrue(PollRules.canVote(config: anyone, currentUser: nil, poll: open, now: now))

        let closed = makePoll(closesAt: now)
        XCTAssertFalse(PollRules.canVote(config: anyone, currentUser: loggedIn, poll: closed, now: now))
    }

    func testCanSeeVoters() {
        XCTAssertFalse(PollRules.canSeeVoters(makePoll(), isSiteAdmin: true))
        XCTAssertFalse(PollRules.canSeeVoters(makePoll(privacy: ._0), isSiteAdmin: true))
        XCTAssertTrue(PollRules.canSeeVoters(makePoll(privacy: ._1), isSiteAdmin: true))
        XCTAssertFalse(PollRules.canSeeVoters(makePoll(privacy: ._1), isSiteAdmin: false))
        XCTAssertTrue(PollRules.canSeeVoters(makePoll(privacy: ._2), isSiteAdmin: false))
    }

    func testCanCreatePoll() {
        func can(_ config: CustomConfigParameters?, admin: Bool = false, chat: Bool = false) -> Bool {
            PollRules.canCreatePoll(config: config, isSiteAdmin: admin, isLiveChat: chat)
        }
        XCTAssertFalse(can(nil))
        XCTAssertFalse(can(CustomConfigParameters(pollCreation: ._0), admin: true))
        XCTAssertFalse(can(CustomConfigParameters(pollCreation: ._1)))
        XCTAssertTrue(can(CustomConfigParameters(pollCreation: ._1), admin: true))
        XCTAssertTrue(can(CustomConfigParameters(pollCreation: ._2)))
        XCTAssertFalse(can(CustomConfigParameters(pollCreation: ._2), chat: true))
        XCTAssertFalse(can(CustomConfigParameters(pollCreation: ._2, useSingleLineCommentInput: true)))
    }

    func testPlainTextDecodesEntities() {
        XCTAssertEqual(PollRules.plainText(fromEscaped: "Tom &amp; Jerry"), "Tom & Jerry")
        XCTAssertEqual(PollRules.plainText(fromEscaped: "&lt;b&gt; &quot;x&quot; &#39;y&#x27;"), "<b> \"x\" 'y'")
        XCTAssertEqual(PollRules.plainText(fromEscaped: "&#128512;"), "😀")
    }

    func testPlainTextDecodesOnce() {
        XCTAssertEqual(PollRules.plainText(fromEscaped: "&amp;lt;"), "&lt;")
    }

    func testPlainTextLeavesLiteralAmpersands() {
        XCTAssertEqual(PollRules.plainText(fromEscaped: "AT&T; R&D & more &"), "AT&T; R&D & more &")
        XCTAssertEqual(PollRules.plainText(fromEscaped: "&#xFFFFFFFF;"), "&#xFFFFFFFF;")
    }
}

final class RecentIdSetTests: XCTestCase {

    func testKeepsOnlyTheMostRecent() {
        var ids = RecentIdSet(capacity: 2)
        ids.insert("a")
        ids.insert("b")
        ids.insert("c")
        XCTAssertFalse(ids.contains("a"))
        XCTAssertTrue(ids.contains("b"))
        XCTAssertTrue(ids.contains("c"))
        XCTAssertEqual(ids.count, 2)
    }

    func testInsertingTwiceDoesNotEvictEarly() {
        var ids = RecentIdSet(capacity: 2)
        ids.insert("a")
        ids.insert("a")
        ids.insert("b")
        XCTAssertTrue(ids.contains("a"))
        XCTAssertTrue(ids.contains("b"))
    }

    func testRemoveFreesItsSlot() {
        var ids = RecentIdSet(capacity: 2)
        ids.insert("a")
        ids.insert("b")
        XCTAssertTrue(ids.remove("a"))
        XCTAssertFalse(ids.remove("a"))
        ids.insert("c")
        XCTAssertTrue(ids.contains("b"))
        XCTAssertTrue(ids.contains("c"))
    }
}
