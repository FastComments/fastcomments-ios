import Foundation
import FastCommentsSwift

/// Determines the layout type for a feed post.
public enum FeedPostType: Sendable {
    case textOnly
    case singleImage
    case multiImage
    case task

    public static func determine(from post: FeedPost) -> FeedPostType {
        // Links take precedence over media (mirrors Android's determinePostType):
        // a post with action links is a "task" card even when it has an image.
        if let links = post.links, !links.isEmpty {
            return .task
        }
        if let media = post.media, !media.isEmpty {
            return media.count == 1 ? .singleImage : .multiImage
        }
        return .textOnly
    }
}
