import SwiftUI

/// Protocol for custom buttons added to the comment input toolbar.
/// Mirrors CustomToolbarButton.java from Android.
public protocol CustomToolbarButton: Identifiable {
    var id: String { get }
    /// SF Symbol name for the button icon.
    var iconSystemName: String { get }
    var contentDescription: String { get }
    var badgeText: String? { get }

    @MainActor func onClick(text: Binding<String>)
    func isEnabled() -> Bool
    func isVisible() -> Bool
}

extension CustomToolbarButton {
    public var badgeText: String? { nil }
    public func isEnabled() -> Bool { true }
    public func isVisible() -> Bool { true }
}
