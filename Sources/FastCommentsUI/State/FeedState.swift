import Foundation
import FastCommentsSwift

/// Serializable snapshot of feed pagination state for save/restore across view lifecycle.
public struct FeedState: Codable, Sendable {
    public var lastPostId: String?
    public var hasMore: Bool
    public var pageSize: Int
    public var newPostsCount: Int
    public var feedPosts: [FeedPost]
    public var myReacts: [String: [String: Bool]]
    public var likeCounts: [String: Int]

    public init(
        lastPostId: String? = nil,
        hasMore: Bool = false,
        pageSize: Int = 10,
        newPostsCount: Int = 0,
        feedPosts: [FeedPost] = [],
        myReacts: [String: [String: Bool]] = [:],
        likeCounts: [String: Int] = [:]
    ) {
        self.lastPostId = lastPostId
        self.hasMore = hasMore
        self.pageSize = pageSize
        self.newPostsCount = newPostsCount
        self.feedPosts = feedPosts
        self.myReacts = myReacts
        self.likeCounts = likeCounts
    }
}
