import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

/// Polls against the real API: posting a comment with a poll, voting, live tallies and the voter list.
@MainActor
final class PollIntegrationTests: IntegrationTestBase {

    override var stableTenantEmail: String { "ios-polls@fctest.com" }

    /// Comments load with the server's config, so this also waits out any config caching after it was saved.
    private func load(_ sdk: FastCommentsSDK, until condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while true {
            try await sdk.load()
            if condition() { return }
            if Date() > deadline {
                XCTFail("Timed out waiting for the saved config to apply")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func enablePolls(_ sdk: FastCommentsSDK, voting: Int = 0) async throws {
        try await createCustomConfig(["pollCreation": 2, "pollVoting": voting])
        try await load(sdk) { sdk.canCreatePoll }
    }

    private func makeDraft(
        privacy: PollPrivacy = ._0, closesDays: Int = 0, requireVote: Bool = false
    ) -> PollDraft {
        PollDraft(
            question: "Best fruit?", options: ["Apple", "Banana"], closesDays: closesDays, privacy: privacy,
            requireVoteToSeeResults: requireVote)
    }

    /// Gives a just-loaded viewer's websocket time to connect before something is broadcast.
    private func letSocketConnect() async throws {
        try await Task.sleep(nanoseconds: 3_000_000_000)
    }

    private func errorCode(_ error: Error) -> String? {
        FastCommentsError(decoding: error)?.code
    }

    // MARK: - Posting

    func testPostedPollLoadsTyped() async throws {
        let sdk = makeSDK()
        try await enablePolls(sdk)

        let posted = try await sdk.postComment(text: "Vote please", poll: makeDraft(privacy: ._2).toInput())
        XCTAssertEqual(posted.poll?.options.count, 2)

        let reader = makeSDK(urlId: sdk.config.urlId)
        try await reader.load()
        let poll = try XCTUnwrap(reader.commentsTree.commentsById[posted.id]?.comment.poll)
        XCTAssertEqual(poll.question, "Best fruit?")
        XCTAssertEqual(poll.options.map(\.label), ["Apple", "Banana"])
        XCTAssertEqual(poll.totalVotes, 0)
        XCTAssertEqual(poll.privacy, ._2)
        sdk.cleanup()
        reader.cleanup()
    }

    func testCloseDateRoundTrips() async throws {
        let sdk = makeSDK()
        try await enablePolls(sdk)

        let posted = try await sdk.postComment(text: "Vote", poll: makeDraft(closesDays: 1).toInput())

        let closesAt = try XCTUnwrap(posted.poll?.closesAt)
        XCTAssertEqual(closesAt.timeIntervalSinceNow, 86_400, accuracy: 120)
        XCTAssertFalse(PollRules.isClosed(try XCTUnwrap(posted.poll)))
        sdk.cleanup()
    }

    func testPollsOffMeansNoPollButton() async throws {
        let sdk = makeSDK()
        try await sdk.load()
        XCTAssertFalse(sdk.canCreatePoll)
        sdk.cleanup()
    }

    func testAdminsOnlyCreation() async throws {
        let urlId = makeUrlId()
        let admin = makeAdminSDK(urlId: urlId)
        try await createCustomConfig(["pollCreation": 1])
        try await load(admin) { admin.canCreatePoll }

        let member = makeSDK(urlId: urlId)
        try await member.load()
        XCTAssertFalse(member.canCreatePoll)
        do {
            try await member.postComment(text: "Sneaky", poll: makeDraft().toInput())
            XCTFail("A non-admin should not be able to attach a poll")
        } catch {
            XCTAssertEqual(errorCode(error), "poll-admins-only")
        }
        admin.cleanup()
        member.cleanup()
    }

    // MARK: - Voting

    func testVoteThenChangeVote() async throws {
        let urlId = makeUrlId()
        let userId = UUID().uuidString
        let sdk = makeSDK(urlId: urlId, userId: userId)
        try await enablePolls(sdk)
        let posted = try await sdk.postComment(text: "Vote", poll: makeDraft().toInput())
        let options = try XCTUnwrap(posted.poll?.options)

        let vote = try await sdk.votePoll(commentId: posted.id, optionId: options[0].id)
        XCTAssertEqual(vote.myPollVotes, [options[0].id])
        XCTAssertEqual(vote.poll.totalVotes, 1)
        // The tree's comment is updated before the call returns.
        let inTree = try XCTUnwrap(sdk.commentsTree.commentsById[posted.id]?.comment)
        XCTAssertEqual(inTree.myPollVotes, [options[0].id])
        XCTAssertEqual(inTree.poll?.options[0].votes, 1)

        let changed = try await sdk.votePoll(commentId: posted.id, optionId: options[1].id)
        XCTAssertEqual(changed.myPollVotes, [options[1].id])
        XCTAssertEqual(changed.poll.totalVotes, 1)
        XCTAssertEqual(changed.poll.options.map(\.votes), [0, 1])

        let again = makeSDK(urlId: urlId, userId: userId)
        try await again.load()
        XCTAssertEqual(again.commentsTree.commentsById[posted.id]?.comment.myPollVotes, [options[1].id])
        sdk.cleanup()
        again.cleanup()
    }

    func testTappingAnOptionVotesAndShowsResults() async throws {
        let sdk = makeSDK()
        try await enablePolls(sdk)
        let posted = try await sdk.postComment(text: "Vote", poll: makeDraft().toInput())
        let optionId = try XCTUnwrap(posted.poll?.options[1].id)

        await sdk.selectPollOption(commentId: posted.id, optionId: optionId)

        let renderable = try XCTUnwrap(sdk.commentsTree.commentsById[posted.id])
        XCTAssertEqual(renderable.pollShowResults, true)
        XCTAssertFalse(renderable.pollSaving)
        XCTAssertNil(renderable.pollError)
        XCTAssertEqual(renderable.comment.myPollVotes, [optionId])
        sdk.cleanup()
    }

    func testRequireVoteZeroesTalliesUntilYouVote() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft(requireVote: true).toInput())
        let options = try XCTUnwrap(posted.poll?.options)
        try await author.votePoll(commentId: posted.id, optionId: options[0].id)

        let reader = makeSDK(urlId: urlId)
        try await reader.load()
        let unvoted = try XCTUnwrap(reader.commentsTree.commentsById[posted.id]?.comment)
        XCTAssertTrue(PollRules.resultsLocked(unvoted))
        XCTAssertEqual(unvoted.poll?.options[0].votes, 0)

        let vote = try await reader.votePoll(commentId: posted.id, optionId: options[1].id)
        XCTAssertEqual(vote.poll.totalVotes, 2)
        author.cleanup()
        reader.cleanup()
    }

    func testAnonymousVoteNeedsLoginByDefault() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft().toInput())
        let optionId = try XCTUnwrap(posted.poll?.options[0].id)

        let anonymous = makeAnonymousSDK(urlId: urlId)
        try await anonymous.load()
        let renderable = try XCTUnwrap(anonymous.commentsTree.commentsById[posted.id])
        XCTAssertFalse(anonymous.canVote(on: try XCTUnwrap(renderable.comment.poll)))

        do {
            try await anonymous.votePoll(commentId: posted.id, optionId: optionId)
            XCTFail("An anonymous vote should be rejected")
        } catch {
            XCTAssertEqual(errorCode(error), "poll-login-required")
        }

        // Tapping says why instead of calling the server.
        await anonymous.selectPollOption(commentId: posted.id, optionId: optionId)
        XCTAssertEqual(renderable.pollError, "Log in to vote")
        XCTAssertFalse(renderable.pollSaving)
        author.cleanup()
        anonymous.cleanup()
    }

    /// The server ties an anonymous vote to a session cookie, which the API client doesn't keep, so "anyone can vote"
    /// reaches the server and comes back as a login error. Android behaves the same way. Apps are expected to use SSO.
    func testAnonymousVoteWhenAnyoneMayIsExplainedOnTheCard() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author, voting: 1)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft().toInput())
        let optionId = try XCTUnwrap(posted.poll?.options[0].id)

        let anonymous = makeAnonymousSDK(urlId: urlId)
        try await anonymous.load()
        XCTAssertTrue(anonymous.canVote(on: try XCTUnwrap(posted.poll)))

        await anonymous.selectPollOption(commentId: posted.id, optionId: optionId)

        let renderable = try XCTUnwrap(anonymous.commentsTree.commentsById[posted.id])
        XCTAssertEqual(renderable.pollError, "Log in to vote")
        XCTAssertFalse(renderable.pollSaving)
        XCTAssertEqual(renderable.comment.poll?.totalVotes, 0)
        author.cleanup()
        anonymous.cleanup()
    }

    func testVoteRejectedByTheServerIsExplainedOnTheCard() async throws {
        let sdk = makeSDK()
        try await enablePolls(sdk)
        let posted = try await sdk.postComment(text: "Vote", poll: makeDraft(closesDays: 1).toInput())
        let optionId = try XCTUnwrap(posted.poll?.options[0].id)

        // No socket, so this SDK still believes the poll is open when the server has closed it.
        sdk.cleanup()
        let patch = try await DefaultAPI.patchPoll(
            tenantId: tenantId,
            commentId: posted.id,
            commentPollPatch: CommentPollPatch(closesAt: ISO8601DateFormatter().string(from: Date())),
            apiConfiguration: adminApiConfig
        )
        XCTAssertEqual(patch.status, .success)

        await sdk.selectPollOption(commentId: posted.id, optionId: optionId)

        let renderable = try XCTUnwrap(sdk.commentsTree.commentsById[posted.id])
        XCTAssertEqual(renderable.pollError, "Poll closed")
        XCTAssertFalse(renderable.pollSaving)
        XCTAssertNil(renderable.pollShowResults, "A rejected vote shouldn't reveal results")
        XCTAssertTrue(renderable.comment.myPollVotes?.isEmpty ?? true)
    }

    // MARK: - Live

    func testOtherViewersSeeLiveTallies() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft().toInput())

        let viewer = makeSDK(urlId: urlId)
        try await viewer.load()
        XCTAssertEqual(viewer.commentsTree.commentsById[posted.id]?.comment.poll?.totalVotes, 0)
        try await letSocketConnect()

        try await author.votePoll(commentId: posted.id, optionId: try XCTUnwrap(posted.poll?.options[1].id))

        try await waitFor(timeout: 20) {
            viewer.commentsTree.commentsById[posted.id]?.comment.poll?.totalVotes == 1
        }
        let seen = try XCTUnwrap(viewer.commentsTree.commentsById[posted.id]?.comment)
        XCTAssertEqual(seen.poll?.options.map(\.votes), [0, 1])
        // Live events carry tallies only, never the viewer's own vote.
        XCTAssertTrue(seen.myPollVotes?.isEmpty ?? true)
        author.cleanup()
        viewer.cleanup()
    }

    /// A close date is what a plain JSONDecoder rejects, which would silently drop these events.
    func testLiveTalliesForAPollWithACloseDate() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft(closesDays: 7).toInput())

        let viewer = makeSDK(urlId: urlId)
        try await viewer.load()
        try await letSocketConnect()

        try await author.votePoll(commentId: posted.id, optionId: try XCTUnwrap(posted.poll?.options[0].id))

        try await waitFor(timeout: 20) {
            viewer.commentsTree.commentsById[posted.id]?.comment.poll?.totalVotes == 1
        }
        XCTAssertNotNil(viewer.commentsTree.commentsById[posted.id]?.comment.poll?.closesAt)
        author.cleanup()
        viewer.cleanup()
    }

    func testNewPollArrivesLive() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)

        let viewer = makeSDK(urlId: urlId)
        try await viewer.load()
        try await letSocketConnect()

        let posted = try await author.postComment(text: "Vote", poll: makeDraft(closesDays: 1).toInput())

        try await waitFor(timeout: 20) { viewer.commentsTree.commentsById[posted.id] != nil }
        let poll = try XCTUnwrap(viewer.commentsTree.commentsById[posted.id]?.comment.poll)
        XCTAssertEqual(poll.question, "Best fruit?")
        XCTAssertNotNil(poll.closesAt)
        author.cleanup()
        viewer.cleanup()
    }

    func testLiveCommentUpdateKeepsMyVote() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft().toInput())
        let optionId = try XCTUnwrap(posted.poll?.options[0].id)

        let voter = makeSDK(urlId: urlId)
        try await voter.load()
        try await letSocketConnect()
        try await voter.votePoll(commentId: posted.id, optionId: optionId)

        // Closing through the API reaches other viewers live.
        let closesAt = Date().addingTimeInterval(-1)
        let patch = try await DefaultAPI.patchPoll(
            tenantId: tenantId,
            commentId: posted.id,
            commentPollPatch: CommentPollPatch(closesAt: ISO8601DateFormatter().string(from: closesAt)),
            apiConfiguration: adminApiConfig
        )
        XCTAssertEqual(patch.status, .success)

        try await waitFor(timeout: 20) {
            voter.commentsTree.commentsById[posted.id]?.comment.poll?.closesAt != nil
        }
        let seen = try XCTUnwrap(voter.commentsTree.commentsById[posted.id]?.comment)
        XCTAssertEqual(seen.myPollVotes, [optionId])
        XCTAssertTrue(PollRules.isClosed(try XCTUnwrap(seen.poll)))
        XCTAssertEqual(seen.poll?.totalVotes, 1)
        author.cleanup()
        voter.cleanup()
    }

    func testClosingAPollWithACloseDateReachesViewersLive() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft(closesDays: 1).toInput())

        let viewer = makeSDK(urlId: urlId)
        try await viewer.load()
        try await letSocketConnect()
        XCTAssertFalse(PollRules.isClosed(try XCTUnwrap(viewer.commentsTree.commentsById[posted.id]?.comment.poll)))

        let patch = try await DefaultAPI.patchPoll(
            tenantId: tenantId,
            commentId: posted.id,
            commentPollPatch: CommentPollPatch(closesAt: ISO8601DateFormatter().string(from: Date())),
            apiConfiguration: adminApiConfig
        )
        XCTAssertEqual(patch.status, .success)

        try await waitFor(timeout: 20) {
            viewer.commentsTree.commentsById[posted.id]?.comment.poll.map { PollRules.isClosed($0) } == true
        }
        author.cleanup()
        viewer.cleanup()
    }

    func testClosingReachesTheAuthorWhoVotedLive() async throws {
        let sdk = makeSDK()
        try await enablePolls(sdk)
        let posted = try await sdk.postComment(text: "Vote", poll: makeDraft(closesDays: 1).toInput())
        let optionId = try XCTUnwrap(posted.poll?.options[0].id)
        try await letSocketConnect()
        await sdk.selectPollOption(commentId: posted.id, optionId: optionId)

        let patch = try await DefaultAPI.patchPoll(
            tenantId: tenantId,
            commentId: posted.id,
            commentPollPatch: CommentPollPatch(closesAt: ISO8601DateFormatter().string(from: Date())),
            apiConfiguration: adminApiConfig
        )
        XCTAssertEqual(patch.status, .success)

        try await waitFor(timeout: 20) {
            sdk.commentsTree.commentsById[posted.id]?.comment.poll.map { PollRules.isClosed($0) } == true
        }
        XCTAssertEqual(sdk.commentsTree.commentsById[posted.id]?.comment.myPollVotes, [optionId])
        sdk.cleanup()
    }

    // MARK: - Voters

    func testPublicPollListsVoters() async throws {
        let sdk = makeSDK()
        try await enablePolls(sdk)
        let posted = try await sdk.postComment(text: "Vote", poll: makeDraft(privacy: ._2).toInput())
        try await sdk.votePoll(commentId: posted.id, optionId: try XCTUnwrap(posted.poll?.options[1].id))

        let result = try await sdk.getPollVoters(commentId: posted.id)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.voters.map(\.optionLabel), ["Banana"])
        XCTAssertFalse(result.hasMore)

        let voterName = try XCTUnwrap(result.voters.first?.name)
        let found = try await sdk.getPollVoters(commentId: posted.id, search: String(voterName.prefix(4)))
        XCTAssertEqual(found.total, 1)
        let missing = try await sdk.getPollVoters(commentId: posted.id, search: "nobody-by-this-name")
        XCTAssertEqual(missing.total, 0)
        sdk.cleanup()
    }

    func testVotersModelPagesThroughEveryVoter() async throws {
        let urlId = makeUrlId()
        let author = makeSDK(urlId: urlId)
        try await enablePolls(author)
        let posted = try await author.postComment(text: "Vote", poll: makeDraft(privacy: ._2).toInput())
        let optionId = try XCTUnwrap(posted.poll?.options[0].id)
        // One more than the server's page size of 25.
        for _ in 0..<26 {
            try await makeSDK(urlId: urlId).votePoll(commentId: posted.id, optionId: optionId)
        }

        let model = PollVotersModel(sdk: author, commentId: posted.id)
        XCTAssertFalse(model.isEmpty, "Nothing has loaded yet, so it isn't known to be empty")
        await model.reload()
        XCTAssertEqual(model.voters.count, 25)
        XCTAssertEqual(model.total, 26)

        // Only the last row triggers the next page.
        await model.loadMoreIfNeeded(afterRowAt: 3)
        XCTAssertEqual(model.voters.count, 25)
        await model.loadMoreIfNeeded(afterRowAt: 24)
        XCTAssertEqual(model.voters.count, 26)

        await model.applySearch("nobody-by-this-name")
        XCTAssertTrue(model.isEmpty)
        author.cleanup()
    }

    func testPollCanAttachToAReply() async throws {
        let sdk = makeSDK()
        try await enablePolls(sdk)
        let parent = try await sdk.postComment(text: "Parent")

        let reply = try await sdk.postComment(text: "Reply", parentId: parent.id, poll: makeDraft().toInput())

        XCTAssertEqual(reply.parentId, parent.id)
        XCTAssertEqual(reply.poll?.question, "Best fruit?")
        let vote = try await sdk.votePoll(commentId: reply.id, optionId: try XCTUnwrap(reply.poll?.options[0].id))
        XCTAssertEqual(vote.poll.totalVotes, 1)
        sdk.cleanup()
    }

    func testAdminsOnlyPollNamesVotersOnlyToAdmins() async throws {
        let urlId = makeUrlId()
        let admin = makeAdminSDK(urlId: urlId)
        try await enablePolls(admin)
        let posted = try await admin.postComment(text: "Vote", poll: makeDraft(privacy: ._1).toInput())
        try await admin.votePoll(commentId: posted.id, optionId: try XCTUnwrap(posted.poll?.options[0].id))

        let adminResult = try await admin.getPollVoters(commentId: posted.id)
        XCTAssertEqual(adminResult.total, 1)
        // The server reports isSiteAdmin false on the load that first creates an SSO admin.
        try await admin.load()
        XCTAssertTrue(admin.isSiteAdmin)
        XCTAssertTrue(PollRules.canSeeVoters(try XCTUnwrap(posted.poll), isSiteAdmin: admin.isSiteAdmin))

        let member = makeSDK(urlId: urlId)
        try await member.load()
        XCTAssertFalse(PollRules.canSeeVoters(try XCTUnwrap(posted.poll), isSiteAdmin: member.isSiteAdmin))
        do {
            _ = try await member.getPollVoters(commentId: posted.id)
            XCTFail("A non-admin should not get the voter list")
        } catch {
            XCTAssertEqual(errorCode(error), "poll-admins-only")
        }
        admin.cleanup()
        member.cleanup()
    }
}
