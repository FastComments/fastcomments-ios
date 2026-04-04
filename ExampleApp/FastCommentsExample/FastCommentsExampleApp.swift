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

/// Minimal feed view for UI testing — inline post creation + feed view.
struct TestFeedView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsFeedSDK
    @State private var postContent: String = ""
    @State private var isPosting: Bool = false

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        _sdk = StateObject(wrappedValue: FastCommentsFeedSDK(config: config))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Write a post...", text: $postContent)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("feed-post-input")
                Button {
                    Task { await submitPost() }
                } label: {
                    if isPosting {
                        ProgressView()
                    } else {
                        Text("Post")
                    }
                }
                .disabled(isPosting || postContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("feed-post-submit")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            FastCommentsFeedView(sdk: sdk)
        }
        .task { try? await sdk.load() }
        .navigationTitle("Feed Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submitPost() async {
        isPosting = true
        defer { isPosting = false }
        let params = CreateFeedPostParams(
            contentHTML: postContent,
            fromUserId: sdk.currentUser?.id,
            fromUserDisplayName: sdk.currentUser?.username ?? sdk.currentUser?.displayName
        )
        do {
            _ = try await sdk.createPost(params: params)
            postContent = ""
        } catch {
            // Keep content for retry
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
