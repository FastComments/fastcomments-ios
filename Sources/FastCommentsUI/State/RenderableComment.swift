import Foundation
import Combine
import FastCommentsSwift

/// Wraps a PublicComment with UI-specific state for rendering.
public final class RenderableComment: RenderableNode {
    public let comment: PublicComment

    @Published public var isRepliesShown: Bool = false
    @Published public var isOnline: Bool = false
    @Published public var hasMoreChildren: Bool = false
    @Published public var isLoadingChildren: Bool = false

    public var childSkip: Int = 0
    public var childPage: Int = 0
    public var childPageSize: Int = 5
    public var newChildComments: [PublicComment]?

    public init(comment: PublicComment) {
        self.comment = comment
        super.init(id: comment.id)

        // Determine if there are more children to load based on API counts
        if let childCount = comment.childCount,
           let nestedChildrenCount = comment.nestedChildrenCount {
            self.hasMoreChildren = childCount > nestedChildrenCount
        } else if let childCount = comment.childCount, childCount > 0 {
            let loadedChildren = comment.children?.count ?? 0
            self.hasMoreChildren = childCount > loadedChildren
        }
    }

    /// Walk up the parentId chain to determine nesting depth.
    public override func nestingLevel(in commentMap: [String: RenderableComment]) -> Int {
        var level = 0
        var currentParentId = comment.parentId
        while let pid = currentParentId, let parent = commentMap[pid] {
            level += 1
            currentParentId = parent.comment.parentId
        }
        return level
    }

    public func resetChildPagination() {
        childSkip = 0
        childPage = 0
    }

    public func getRemainingChildCount() -> Int {
        let childCount = comment.childCount ?? 0
        let loaded = comment.children?.count ?? 0
        return max(0, childCount - loaded - childSkip)
    }

    public func addNewChildComment(_ comment: PublicComment) {
        if newChildComments == nil {
            newChildComments = []
        }
        newChildComments?.append(comment)
    }

    public func getNewChildCommentsCount() -> Int {
        newChildComments?.count ?? 0
    }

    public func getAndClearNewChildComments() -> [PublicComment]? {
        let comments = newChildComments
        newChildComments = nil
        return comments
    }
}
