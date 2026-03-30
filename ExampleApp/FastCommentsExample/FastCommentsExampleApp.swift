import SwiftUI

@main
struct FastCommentsExampleApp: App {
    var body: some Scene {
        WindowGroup {
            if let viewName = screenshotViewName {
                screenshotView(name: viewName)
            } else {
                ContentView()
            }
        }
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
