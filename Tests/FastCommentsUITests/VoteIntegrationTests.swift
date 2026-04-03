import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class VoteIntegrationTests: IntegrationTestBase {

    override var stableTenantEmail: String { "ios-vote@fctest.com" }

    func testUpvoteComment() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Vote me up")
        let response = try await sdk.voteComment(commentId: comment.id, isUpvote: true)

        let renderable = sdk.commentsTree.commentsById[comment.id]!
        XCTAssertEqual(renderable.comment.votesUp, 1)
        XCTAssertEqual(renderable.comment.isVotedUp, true)
        XCTAssertEqual(renderable.comment.isVotedDown, false)
        XCTAssertNotNil(response.voteId)
    }

    func testDownvoteComment() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Vote me down")
        _ = try await sdk.voteComment(commentId: comment.id, isUpvote: false)

        let renderable = sdk.commentsTree.commentsById[comment.id]!
        XCTAssertEqual(renderable.comment.votesDown, 1)
        XCTAssertEqual(renderable.comment.isVotedDown, true)
        XCTAssertEqual(renderable.comment.isVotedUp, false)
    }

    func testUpvoteThenDownvote() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Toggle vote")
        _ = try await sdk.voteComment(commentId: comment.id, isUpvote: true)
        _ = try await sdk.voteComment(commentId: comment.id, isUpvote: false)

        let renderable = sdk.commentsTree.commentsById[comment.id]!
        XCTAssertEqual(renderable.comment.votesUp, 0)
        XCTAssertEqual(renderable.comment.votesDown, 1)
        XCTAssertEqual(renderable.comment.isVotedDown, true)
        XCTAssertEqual(renderable.comment.isVotedUp, false)
        XCTAssertEqual(renderable.comment.votes, -1)
    }

    func testDownvoteThenUpvote() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Toggle vote reverse")
        _ = try await sdk.voteComment(commentId: comment.id, isUpvote: false)
        _ = try await sdk.voteComment(commentId: comment.id, isUpvote: true)

        let renderable = sdk.commentsTree.commentsById[comment.id]!
        XCTAssertEqual(renderable.comment.votesDown, 0)
        XCTAssertEqual(renderable.comment.votesUp, 1)
        XCTAssertEqual(renderable.comment.isVotedUp, true)
        XCTAssertEqual(renderable.comment.isVotedDown, false)
        XCTAssertEqual(renderable.comment.votes, 1)
    }

    func testDeleteVote() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Delete my vote")
        let voteResponse = try await sdk.voteComment(commentId: comment.id, isUpvote: true)
        let voteId = voteResponse.voteId!

        try await sdk.deleteCommentVote(commentId: comment.id, voteId: voteId)

        let renderable = sdk.commentsTree.commentsById[comment.id]!
        XCTAssertEqual(renderable.comment.isVotedUp, false)
        XCTAssertEqual(renderable.comment.isVotedDown, false)
        XCTAssertNil(renderable.comment.myVoteId)
        XCTAssertEqual(renderable.comment.votesUp, 0)
    }

    func testVoteUpdatesNetVotes() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Net votes check")
        _ = try await sdk.voteComment(commentId: comment.id, isUpvote: true)

        let renderable = sdk.commentsTree.commentsById[comment.id]!
        XCTAssertEqual(renderable.comment.votes, 1)
    }

    func testVoteReturnsVoteId() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let comment = try await sdk.postComment(text: "Vote ID check")
        let response = try await sdk.voteComment(commentId: comment.id, isUpvote: true)

        XCTAssertNotNil(response.voteId)
        XCTAssertFalse(response.voteId!.isEmpty)
    }

    func testMultipleVotesOnDifferentComments() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let c1 = try await sdk.postComment(text: "Comment A")
        let c2 = try await sdk.postComment(text: "Comment B")

        _ = try await sdk.voteComment(commentId: c1.id, isUpvote: true)
        _ = try await sdk.voteComment(commentId: c2.id, isUpvote: true)

        XCTAssertEqual(sdk.commentsTree.commentsById[c1.id]!.comment.votesUp, 1)
        XCTAssertEqual(sdk.commentsTree.commentsById[c2.id]!.comment.votesUp, 1)
    }
}
