import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Threaded comments with SSO, detailed theme, and heart vote style.
///
/// Shows how to:
/// - Create a config with Simple SSO for user identity
/// - Load comments and display them
/// - Apply a detailed custom theme (every color, typography, corner radius)
/// - Use heart vote style instead of up/down
/// - Handle user click events
struct CommentsExampleView: View {
    // 1. Create the SDK with SSO so the user has an identity.
    //
    // WARNING: Simple SSO is NOT secure and should only be used for demos/testing.
    // Anyone can impersonate any user with Simple SSO.
    // For production, use Secure SSO where your backend generates a signed token
    // with your API secret. See SecureSSOExampleView for the production pattern.
    //
    @StateObject private var sdk: FastCommentsSDK = {
        let userData = SimpleSSOUserData(
            username: "Example User",
            email: "user@example.com",
            avatar: "https://staticm.fastcomments.com/1639362726066-DSC_0841.JPG"
        )
        let sso = FastCommentsSSO.createSimple(simpleSSOUserData: userData)
        let token = try? sso.prepareToSend()

        let config = FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "test",
            url: "https://example.com/page-1",
            pageTitle: "Example Page",
            sso: token
        )
        return FastCommentsSDK(config: config)
    }()

    @State private var selectedUser: UserInfo?

    var body: some View {
        // 2. Embed the comments view with heart vote style
        FastCommentsView(sdk: sdk, voteStyle: ._1)
            .onUserClick { context, userInfo, source in
                selectedUser = userInfo
            }
            .fastCommentsTheme(customTheme)
            .task {
                try? await sdk.load()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .alert("User Profile", isPresented: .constant(selectedUser != nil)) {
                Button("OK") { selectedUser = nil }
            } message: {
                if let user = selectedUser {
                    Text("Tapped on \(user.displayName)")
                }
            }
    }

    // 3. Detailed theme customization — demonstrates every color property
    private var customTheme: FastCommentsTheme {
        var theme = FastCommentsTheme.modern

        // Primary colors
        theme.primaryColor = .indigo
        theme.primaryLightColor = .indigo.opacity(0.6)
        theme.primaryDarkColor = Color(red: 0.2, green: 0.1, blue: 0.5)

        // Action button colors
        theme.actionButtonColor = .indigo
        theme.replyButtonColor = .indigo
        theme.toggleRepliesButtonColor = .indigo.opacity(0.8)
        theme.loadMoreButtonTextColor = .indigo

        // Vote colors
        theme.voteActiveColor = .red       // Heart fill color
        theme.voteCountColor = .primary
        theme.voteCountZeroColor = .secondary

        // Link colors
        theme.linkColor = .indigo
        theme.linkColorPressed = .indigo.opacity(0.5)

        // Dialog / sheet header
        theme.dialogHeaderBackgroundColor = .indigo
        theme.dialogHeaderTextColor = .white

        // Online presence indicator
        theme.onlineIndicatorColor = .green

        // Layout
        theme.cornerRadius = .large
        theme.commentStyle = .card
        theme.showShadows = true
        theme.showThreadLine = true
        theme.threadLineColor = .indigo.opacity(0.15)
        theme.animateVotes = true

        return theme
    }
}
