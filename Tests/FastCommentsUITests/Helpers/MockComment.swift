import Foundation
import FastCommentsSwift

enum MockComment {
    static func make(
        id: String = UUID().uuidString,
        userId: String? = nil,
        commenterName: String = "Test User",
        commentHTML: String = "<p>Test comment</p>",
        parentId: String? = nil,
        date: Date? = Date(),
        votes: Int? = 0,
        verified: Bool = true,
        displayLabel: String? = nil,
        childCount: Int? = nil,
        children: [PublicComment]? = nil,
        isPinned: Bool? = nil,
        isDeleted: Bool? = nil,
        isLocked: Bool? = nil
    ) -> PublicComment {
        PublicComment(
            id: id,
            userId: userId,
            commenterName: commenterName,
            commentHTML: commentHTML,
            parentId: parentId,
            date: date,
            votes: votes,
            verified: verified,
            isPinned: isPinned,
            isLocked: isLocked,
            displayLabel: displayLabel,
            isDeleted: isDeleted,
            childCount: childCount,
            children: children
        )
    }
}
