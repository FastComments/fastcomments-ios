import Foundation
import FastCommentsSwift

/// Determines the layout type for a feed post.
public enum FeedPostType: Sendable {
    case textOnly
    case singleImage
    case multiImage
    case task

    public static func determine(from post: FeedPost) -> FeedPostType {
        if let media = post.media, !media.isEmpty {
            if media.count == 1 {
                return .singleImage
            } else {
                return .multiImage
            }
        }
        if let links = post.links, !links.isEmpty {
            return .task
        }
        return .textOnly
    }
}
