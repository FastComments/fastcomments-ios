import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Simple SSO — client-side user identity without a backend.
///
/// Use this for demos and testing. For production, use Secure SSO instead.
///
/// Shows how to:
/// - Create SimpleSSOUserData with user details
/// - Generate an SSO token
/// - Pass it to the widget config
struct SimpleSSOExampleView: View {
    @StateObject private var sdk: FastCommentsSDK = {
        // 1. Define the user's identity
        let userData = SimpleSSOUserData(
            username: "Jane Doe",
            email: "jane@example.com",
            avatar: "https://i.pravatar.cc/150?u=jane"
        )

        // 2. Create the SSO object and generate a token
        let sso = FastCommentsSSO.createSimple(simpleSSOUserData: userData)
        let token = try? sso.prepareToSend()

        // 3. Pass the token in the widget config
        let config = FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "example-simple-sso",
            sso: token
        )

        return FastCommentsSDK(config: config)
    }()

    var body: some View {
        FastCommentsView(sdk: sdk)
            .task {
                try? await sdk.load()
            }
            .navigationTitle("Simple SSO")
            .navigationBarTitleDisplayMode(.inline)
    }
}
