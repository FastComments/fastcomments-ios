import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Themed comments view for UI testing — driven by launch arguments including theme name.
struct TestThemedCommentsView: View {
    let config: FastCommentsWidgetConfig
    let theme: FastCommentsTheme
    @StateObject private var sdk: FastCommentsSDK

    init(config: FastCommentsWidgetConfig, theme: FastCommentsTheme) {
        self.config = config
        self.theme = theme
        _sdk = StateObject(wrappedValue: FastCommentsSDK(config: config))
    }

    var body: some View {
        FastCommentsView(sdk: sdk)
            .fastCommentsTheme(theme)
            .task { try? await sdk.load() }
            .navigationTitle("Test")
            .navigationBarTitleDisplayMode(.inline)
    }

    /// Build a theme from a name string passed via launch arguments.
    static func makeTheme(named name: String) -> FastCommentsTheme {
        switch name {
        case "card":
            var theme = FastCommentsTheme.modern
            theme.primaryColor = Color(red: 0.39, green: 0.35, blue: 1.0) // indigo
            theme.primaryLightColor = Color(red: 0.39, green: 0.35, blue: 1.0).opacity(0.7)
            theme.voteActiveColor = Color(red: 0.39, green: 0.35, blue: 1.0)
            return theme
        case "bubble":
            var theme = FastCommentsTheme()
            theme.commentStyle = .bubble
            theme.cornerRadius = .large
            theme.showShadows = false
            theme.showThreadLine = false
            theme.primaryColor = Color(red: 0.0, green: 0.73, blue: 0.65) // teal
            theme.primaryLightColor = Color(red: 0.0, green: 0.73, blue: 0.65).opacity(0.7)
            theme.voteActiveColor = Color(red: 0.0, green: 0.73, blue: 0.65)
            theme.commentBackgroundColor = Color(red: 0.15, green: 0.15, blue: 0.18)
            theme.containerBackgroundColor = Color(red: 0.1, green: 0.1, blue: 0.12)
            return theme
        default: // "flat"
            return FastCommentsTheme.default
        }
    }
}
