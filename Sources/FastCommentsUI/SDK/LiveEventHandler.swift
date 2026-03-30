import Foundation
import FastCommentsSwift

/// Helpers for dispatching live events to the appropriate handler.
enum LiveEventHandler {

    /// Convert a PubSubCommentUserBadgeInfo to a CommentUserBadgeInfo.
    static func toCommentUserBadgeInfo(_ pubSub: PubSubCommentUserBadgeInfo) -> CommentUserBadgeInfo? {
        guard let id = pubSub.id,
              let type = pubSub.type,
              let description = pubSub.description else { return nil }
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

    /// Convert a PubSubComment to a PublicComment for tree operations.
    static func toPublicComment(_ pubSub: PubSubComment) -> PublicComment {
        PublicComment(
            id: pubSub.id ?? "",
            userId: pubSub.userId,
            commenterName: pubSub.commenterName ?? "",
            commenterLink: pubSub.commenterLink,
            commentHTML: pubSub.commentHTML ?? "",
            parentId: pubSub.parentId,
            date: pubSub.date.flatMap { ISO8601DateFormatter().date(from: $0) },
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
            feedbackIds: pubSub.feedbackIds
        )
    }
}
