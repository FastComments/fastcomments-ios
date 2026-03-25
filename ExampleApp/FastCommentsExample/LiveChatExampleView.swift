import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Real-time live chat mode.
///
/// Shows how to:
/// - Configure the SDK for live chat (oldest-first sort)
/// - Use Simple SSO to give the user an identity
/// - Embed the LiveChatView
struct LiveChatExampleView: View {
    @StateObject private var sdk: FastCommentsSDK = {
        // 1. Create config with SSO so the user has a name in chat
        let userData = SimpleSSOUserData(
            username: "ChatUser",
            email: "chat@example.com",
            avatar: nil
        )
        let sso = FastCommentsSSO.createSimple(simpleSSOUserData: userData)
        let token = try? sso.prepareToSend()

        let config = FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "example-live-chat",
            sso: token
        )

        let sdk = FastCommentsSDK(config: config)

        // 2. Use oldest-first sort for chat chronology
        sdk.defaultSortDirection = .of
        sdk.showLiveRightAway = true

        return sdk
    }()

    var body: some View {
        // 3. Embed the live chat view
        LiveChatView(sdk: sdk)
            .onCommentPosted { comment in
                print("Sent: \(comment.commentHTML)")
            }
            .task {
                try? await sdk.load()
            }
            .navigationTitle("Live Chat")
            .navigationBarTitleDisplayMode(.inline)
    }
}
