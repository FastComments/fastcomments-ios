import Foundation
import FastCommentsSwift

/// Extracted user information from a comment or feed post.
public struct UserInfo: Sendable {
    public let userId: String?
    public let userName: String?
    public let userAvatarUrl: String?

    public var displayName: String {
        userName ?? "Anonymous"
    }

    public init(userId: String?, userName: String?, userAvatarUrl: String?) {
        self.userId = userId
        self.userName = userName
        self.userAvatarUrl = userAvatarUrl
    }

    public static func from(_ comment: PublicComment) -> UserInfo {
        UserInfo(
            userId: comment.userId,
            userName: comment.commenterName,
            userAvatarUrl: comment.avatarSrc
        )
    }

    public static func from(_ post: FeedPost) -> UserInfo {
        UserInfo(
            userId: post.fromUserId,
            userName: post.fromUserDisplayName,
            userAvatarUrl: post.fromUserAvatar
        )
    }

    public static func from(_ comment: PubSubComment) -> UserInfo {
        UserInfo(
            userId: comment.userId,
            userName: comment.commenterName,
            userAvatarUrl: comment.avatarSrc
        )
    }
}
