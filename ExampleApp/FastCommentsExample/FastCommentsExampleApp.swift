import SwiftUI
import FastCommentsUI
import FastCommentsSwift

@main
struct FastCommentsExampleApp: App {
    var body: some Scene {
        WindowGroup {
            if let testConfig = testConfig {
                NavigationStack {
                    TestCommentsView(config: testConfig)
                }
            } else if let chatConfig = testChatConfig {
                NavigationStack {
                    TestLiveChatView(config: chatConfig)
                }
            } else if let feedConfig = testFeedConfig {
                NavigationStack {
                    TestFeedView(config: feedConfig)
                }
            } else if let (config, theme) = testThemeConfig {
                NavigationStack {
                    TestThemedCommentsView(config: config, theme: theme)
                }
            } else if let viewName = screenshotViewName {
                screenshotView(name: viewName)
            } else {
                ContentView()
            }
        }
    }

    /// Check for "-test" mode with tenantId/urlId/sso launch arguments
    private var testConfig: FastCommentsWidgetConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-test"),
              idx + 3 < args.count else { return nil }
        let tenantId = args[idx + 1]
        let urlId = args[idx + 2]
        let sso = args[idx + 3]
        return FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: sso)
    }

    /// Check for "-test-chat" mode with tenantId/urlId/sso launch arguments
    private var testChatConfig: FastCommentsWidgetConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-test-chat"),
              idx + 3 < args.count else { return nil }
        return FastCommentsWidgetConfig(tenantId: args[idx + 1], urlId: args[idx + 2], sso: args[idx + 3])
    }

    /// Check for "-test-feed" mode with tenantId/urlId/sso launch arguments
    private var testFeedConfig: FastCommentsWidgetConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-test-feed"),
              idx + 3 < args.count else { return nil }
        return FastCommentsWidgetConfig(tenantId: args[idx + 1], urlId: args[idx + 2], sso: args[idx + 3])
    }

    /// Check for "-test-theme" mode with tenantId/urlId/sso/themeName launch arguments
    private var testThemeConfig: (FastCommentsWidgetConfig, FastCommentsTheme)? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-test-theme"),
              idx + 4 < args.count else { return nil }
        let config = FastCommentsWidgetConfig(tenantId: args[idx + 1], urlId: args[idx + 2], sso: args[idx + 3])
        let theme = TestThemedCommentsView.makeTheme(named: args[idx + 4])
        return (config, theme)
    }

    /// Check for "-screenshot <viewname>" in launch arguments
    private var screenshotViewName: String? {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-screenshot"), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }

    @ViewBuilder
    private func screenshotView(name: String) -> some View {
        switch name {
        case "comments":
            NavigationStack { CommentsExampleView() }
        case "chat":
            NavigationStack { LiveChatExampleView() }
        case "feed":
            NavigationStack { FeedExampleView() }
        case "toolbar":
            NavigationStack { ToolbarShowcaseView() }
        case "sso":
            NavigationStack { SimpleSSOExampleView() }
        case "tour":
            ScreenshotTourView()
        default:
            ContentView()
        }
    }
}

/// Minimal comments view for UI testing — driven entirely by launch arguments.
struct TestCommentsView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsSDK

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsSDK(config: config))
    }

    var body: some View {
        FastCommentsView(sdk: sdk)
            .task { try? await sdk.load() }
            .navigationTitle("Test")
            .navigationBarTitleDisplayMode(.inline)
    }
}
