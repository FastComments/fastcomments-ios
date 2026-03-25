import Foundation

/// A "Show N new comments/replies" button in the comment list.
public final class RenderableButton: RenderableNode {
    public enum ButtonType: Sendable {
        case newRootComments
        case newChildComments
    }

    public let buttonType: ButtonType
    public private(set) var commentCount: Int
    public let parentId: String?

    public init(buttonType: ButtonType, commentCount: Int, parentId: String? = nil) {
        self.buttonType = buttonType
        self.commentCount = commentCount
        self.parentId = parentId

        let id: String
        switch buttonType {
        case .newRootComments:
            id = "button-new-root"
        case .newChildComments:
            id = "button-new-child-\(parentId ?? "unknown")"
        }
        super.init(id: id)
    }

    public func updateCount(_ count: Int) {
        self.commentCount = count
    }
}
