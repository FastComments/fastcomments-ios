import Foundation
import FastCommentsSwift

/// Helpers for dispatching live events to the appropriate handler.
enum LiveEventHandler {

    /// Convert a PubSubCommentUserBadgeInfo to a CommentUserBadgeInfo.
    static func toCommentUserBadgeInfo(_ pubSub: PubSubCommentUserBadgeInfo) -> CommentUserBadgeInfo? {
        guard let id = pubSub.id,
            let type = pubSub.type,
            let description = pubSub.description
        else { return nil }
        return CommentUserBadgeInfo(
            id: id,
            type: type,
            description: description,
            displayLabel: pubSub.displayLabel,
            displaySrc: pubSub.displaySrc,
            backgroundColor: pubSub.backgroundColor,
            borderColor: pubSub.borderColor,
            textColor: pubSub.textColor,
            cssClass: pubSub.cssClass
        )
    }

    private static let dateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let dateFormatter = ISO8601DateFormatter()

    /// The server sends fractional seconds, which a default ISO8601DateFormatter won't parse.
    static func parseDate(_ string: String) -> Date? {
        dateFormatterWithFractionalSeconds.date(from: string) ?? dateFormatter.date(from: string)
    }

    /// Live events describe the comment for everyone, so they never carry this viewer's own state or the replies loaded
    /// so far. An update keeps those from the comment it replaces.
    static func carryingViewerState(from existing: PublicComment, to updated: PublicComment) -> PublicComment {
        var merged = updated
        merged.myPollVotes = existing.myPollVotes
        merged.myVoteId = existing.myVoteId
        merged.isVotedUp = existing.isVotedUp
        merged.isVotedDown = existing.isVotedDown
        merged.isFlagged = existing.isFlagged
        merged.isBlocked = existing.isBlocked
        merged.hasChildren = existing.hasChildren
        merged.childCount = existing.childCount
        merged.nestedChildrenCount = existing.nestedChildrenCount
        merged.children = existing.children
        merged.badges = existing.badges
        merged.editKey = existing.editKey
        return merged
    }

    /// Convert a PubSubComment to a PublicComment for tree operations.
    static func toPublicComment(_ pubSub: PubSubComment) -> PublicComment {
        PublicComment(
            id: pubSub.id ?? "",
            userId: pubSub.userId,
            commenterName: pubSub.commenterName ?? "",
            commenterLink: pubSub.commenterLink,
            commentHTML: pubSub.commentHTML ?? "",
            parentId: pubSub.parentId,
            date: pubSub.date.flatMap(parseDate),
            votes: pubSub.votes,
            votesUp: pubSub.votesUp,
            votesDown: pubSub.votesDown,
            verified: pubSub.verified ?? false,
            avatarSrc: pubSub.avatarSrc,
            hasImages: pubSub.hasImages,
            isByAdmin: pubSub.isByAdmin,
            isByModerator: pubSub.isByModerator,
            isPinned: pubSub.isPinned,
            isLocked: pubSub.isLocked,
            displayLabel: pubSub.displayLabel,
            rating: pubSub.rating,
            viewCount: pubSub.viewCount,
            isDeleted: pubSub.isDeleted,
            isDeletedUser: pubSub.isDeletedUser,
            isSpam: pubSub.isSpam,
            anonUserId: pubSub.anonUserId,
            feedbackIds: pubSub.feedbackIds,
            poll: pubSub.poll
        )
    }
}
