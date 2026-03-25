import Foundation

/// Request parameters for loading child comments with pagination.
public struct GetChildrenRequest: Sendable {
    public let parentId: String
    public let skip: Int?
    public let limit: Int?
    public let isLoadMore: Bool

    public init(parentId: String, skip: Int? = nil, limit: Int? = nil, isLoadMore: Bool = false) {
        self.parentId = parentId
        self.skip = skip
        self.limit = limit
        self.isLoadMore = isLoadMore
    }
}
