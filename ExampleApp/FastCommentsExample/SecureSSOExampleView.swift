import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Secure SSO — production user identity with server-side token generation.
///
/// In production, your backend generates the SSO token using your API key.
/// The app fetches the token from your backend and passes it to the widget.
///
/// Shows how to:
/// - Fetch an SSO token from your backend
/// - Pass it to the widget config
/// - (For reference) How the backend generates the token
struct SecureSSOExampleView: View {
    @StateObject private var sdk = FastCommentsSDK(
        config: FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "example-secure-sso"
        )
    )

    @State private var isLoadingToken = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoadingToken {
                ProgressView("Loading SSO token...")
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                FastCommentsView(sdk: sdk)
            }
        }
        .task {
            await loadWithSSO()
        }
        .navigationTitle("Secure SSO")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadWithSSO() async {
        do {
            // 1. Fetch the SSO token from YOUR backend
            //    Your backend should call FastCommentsSSO.createSecure() with your API key.
            //    See the "Backend Reference" section below for how that works.
            let token = try await fetchSSOTokenFromBackend()

            // 2. Create a new config with the SSO token and reload
            //    In a real app, you'd pass the token when creating the SDK.
            //    This example shows the pattern of fetching then loading.
            _ = token  // Use this token in your config's sso field

            isLoadingToken = false
            try await sdk.load()
        } catch {
            errorMessage = error.localizedDescription
            isLoadingToken = false
        }
    }

    /// Replace this with a real API call to your backend.
    private func fetchSSOTokenFromBackend() async throws -> String {
        // Your backend endpoint should return the SSO token string.
        // Example: let (data, _) = try await URLSession.shared.data(from: ssoEndpoint)
        //          return String(data: data, encoding: .utf8)!

        // For this demo, we generate the token locally (DON'T do this in production —
        // your API key must stay on the server).
        let userData = SecureSSOUserData(
            id: "user-123",
            email: "secure@example.com",
            username: "SecureUser",
            avatar: "https://i.pravatar.cc/150?u=secure"
        )
        let sso = try FastCommentsSSO.createSecure(apiKey: "YOUR_API_KEY", secureSSOUserData: userData)
        return try sso.prepareToSend() ?? ""
    }
}

// MARK: - Backend Reference
//
// On your server (Node.js, Python, etc.), generate the token like this:
//
//   let userData = SecureSSOUserData(
//       id: "user-123",
//       email: "user@example.com",
//       username: "Display Name",
//       avatar: "https://example.com/avatar.jpg"
//   )
//   let sso = try FastCommentsSSO.createSecure(apiKey: "YOUR_API_KEY", secureSSOUserData: userData)
//   let token = try sso.prepareToSend()
//   // Return `token` to your iOS app via your API
