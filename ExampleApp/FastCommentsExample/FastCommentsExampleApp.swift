import SwiftUI
import FastCommentsUI
import FastCommentsSwift

@main
struct FastCommentsExampleApp: App {
    var body: some Scene {
        WindowGroup {
            if isBenchmarkMode {
                NavigationStack {
                    BenchmarkView(autoRun: true)
                }
            } else if let feedLifecycleTestConfig = feedLifecycleTestConfig {
                NavigationStack {
                    FeedLifecycleTestView(config: feedLifecycleTestConfig)
                }
            } else if let fullFeedTestConfig = fullFeedTestConfig {
                NavigationStack {
                    FullFeedComposerTestView(config: fullFeedTestConfig)
                }
            } else if let feedComposerTestConfig = feedComposerTestConfig {
                NavigationStack {
                    FeedComposerTestView(config: feedComposerTestConfig)
                }
            } else if let feedTestConfig = feedTestConfig {
                NavigationStack {
                    TestFeedView(config: feedTestConfig)
                }
            } else if let testConfig = testConfig {
                NavigationStack {
                    TestCommentsView(config: testConfig)
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

    /// Check for "-feed-test" mode with tenantId/urlId/sso launch arguments
    private var feedTestConfig: FastCommentsWidgetConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-feed-test"),
              idx + 3 < args.count else { return nil }
        let tenantId = args[idx + 1]
        let urlId = args[idx + 2]
        let sso = args[idx + 3]
        return FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: sso)
    }

    /// Check for "-feed-composer-test" mode with tenantId/urlId/sso launch arguments
    private var feedComposerTestConfig: FastCommentsWidgetConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-feed-composer-test"),
              idx + 3 < args.count else { return nil }
        let tenantId = args[idx + 1]
        let urlId = args[idx + 2]
        let sso = args[idx + 3]
        return FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: sso)
    }

    /// Check for "-full-feed-test" mode with tenantId/urlId/sso launch arguments
    private var fullFeedTestConfig: FastCommentsWidgetConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-full-feed-test"),
              idx + 3 < args.count else { return nil }
        let tenantId = args[idx + 1]
        let urlId = args[idx + 2]
        let sso = args[idx + 3]
        return FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: sso)
    }

    /// Check for "-feed-lifecycle-test" mode with tenantId/urlId/sso launch arguments
    private var feedLifecycleTestConfig: FastCommentsWidgetConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-feed-lifecycle-test"),
              idx + 3 < args.count else { return nil }
        let tenantId = args[idx + 1]
        let urlId = args[idx + 2]
        let sso = args[idx + 3]
        return FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: sso)
    }

    private var isBenchmarkMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-benchmark")
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
