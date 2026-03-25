import SwiftUI

/// SwiftUI EnvironmentKey for propagating the FastComments theme down the view hierarchy.
private struct FastCommentsThemeKey: EnvironmentKey {
    static let defaultValue = FastCommentsTheme()
}

extension EnvironmentValues {
    public var fastCommentsTheme: FastCommentsTheme {
        get { self[FastCommentsThemeKey.self] }
        set { self[FastCommentsThemeKey.self] = newValue }
    }
}

extension View {
    /// Apply a FastComments theme to this view and all its descendants.
    public func fastCommentsTheme(_ theme: FastCommentsTheme) -> some View {
        environment(\.fastCommentsTheme, theme)
    }
}
