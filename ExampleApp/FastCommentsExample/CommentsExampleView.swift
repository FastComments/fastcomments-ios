import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Basic threaded comments widget.
///
/// Shows how to:
/// - Create a config and SDK instance
/// - Load comments and display them
/// - Apply a custom theme
/// - Handle user click events
struct CommentsExampleView: View {
    // 1. Create the SDK with your tenant ID and a page identifier
    @StateObject private var sdk = FastCommentsSDK(
        config: FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "example-page-1",
            url: "https://example.com/page-1",
            pageTitle: "Example Page"
        )
    )

    @State private var selectedUser: UserInfo?

    var body: some View {
        // 2. Embed the comments view
        FastCommentsView(sdk: sdk)
            .onUserClick { context, userInfo, source in
                // 3. Handle user avatar/name taps
                selectedUser = userInfo
            }
            .task {
                // 4. Load comments when the view appears
                try? await sdk.load()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .alert("User Profile", isPresented: .constant(selectedUser != nil)) {
                Button("OK") { selectedUser = nil }
            } message: {
                if let user = selectedUser {
                    Text("Tapped on \(user.username ?? "Unknown")")
                }
            }
            .onAppear {
                // 5. Optionally customize the theme
                var theme = FastCommentsTheme()
                theme.primaryColor = .blue
                theme.actionButtonColor = .indigo
                sdk.theme = theme
            }
    }
}
