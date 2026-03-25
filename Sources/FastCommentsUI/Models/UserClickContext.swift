import Foundation
import FastCommentsSwift

/// Context for when a user's name or avatar is tapped.
public enum UserClickContext: Sendable {
    case comment(PublicComment)
    case feedPost(FeedPost)
}
