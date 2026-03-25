import Foundation
import FastCommentsSwift

/// Base class for items rendered in the comments list.
/// Subclasses: RenderableComment, RenderableButton, DateSeparator.
public class RenderableNode: Identifiable, ObservableObject {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    /// Calculate the nesting depth of this node by walking up parentId chains.
    public func nestingLevel(in commentMap: [String: RenderableComment]) -> Int {
        return 0
    }
}

/// Date separator row for live chat mode.
public final class DateSeparator: RenderableNode {
    public let date: Date

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public init(date: Date) {
        self.date = date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let id = "date-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        super.init(id: id)
    }
}
