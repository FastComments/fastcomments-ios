import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Automatically tours through each example screen for screenshotting.
/// Launch with: SCREENSHOT_TOUR=1 environment variable or tap "Screenshot Tour" in the list.
struct ScreenshotTourView: View {
    @State private var currentScreen: TourScreen = .comments
    @State private var showTour = true

    enum TourScreen: String, CaseIterable {
        case comments = "comments"
        case liveChat = "livechat"
        case feed = "feed"
        case simpleSSO = "simple-sso"
    }

    var body: some View {
        ZStack {
            switch currentScreen {
            case .comments:
                NavigationStack {
                    CommentsExampleView()
                }
            case .liveChat:
                NavigationStack {
                    LiveChatExampleView()
                }
            case .feed:
                NavigationStack {
                    FeedExampleView()
                }
            case .simpleSSO:
                NavigationStack {
                    SimpleSSOExampleView()
                }
            }

            // Navigation overlay
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    ForEach(TourScreen.allCases, id: \.rawValue) { screen in
                        Button {
                            withAnimation { currentScreen = screen }
                        } label: {
                            Text(screen.rawValue)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(currentScreen == screen ? Color.accentColor : Color.secondary.opacity(0.3))
                                .foregroundStyle(currentScreen == screen ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.bottom, 90) // Above input bar
            }
        }
    }
}
