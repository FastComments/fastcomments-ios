import SwiftUI

/// Protocol for custom buttons added to the feed post creation toolbar.
/// Mirrors FeedCustomToolbarButton.java from Android.
public protocol FeedCustomToolbarButton: Identifiable {
    var id: String { get }
    /// SF Symbol name for the button icon.
    var iconSystemName: String { get }
    var contentDescription: String { get }
    var badgeText: String? { get }

    @MainActor func onClick(content: Binding<String>)
    func isEnabled() -> Bool
    func isVisible() -> Bool
}

extension FeedCustomToolbarButton {
    public var badgeText: String? { nil }
    public func isEnabled() -> Bool { true }
    public func isVisible() -> Bool { true }
}
