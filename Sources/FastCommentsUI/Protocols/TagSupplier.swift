import Foundation
import FastCommentsSwift

/// Supplies tags for filtering feed posts, optionally based on the current user.
public protocol TagSupplier: Sendable {
    func getTags(currentUser: UserSessionInfo?) -> [String]?
}
