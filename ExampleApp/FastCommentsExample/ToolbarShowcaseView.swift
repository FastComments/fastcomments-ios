import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Custom toolbar buttons in the comment input bar.
///
/// Shows how to:
/// - Implement the CustomToolbarButton protocol
/// - Add multiple custom buttons with icons, badges, and actions
/// - Apply a theme to the toolbar
struct ToolbarShowcaseView: View {
    @StateObject private var sdk: FastCommentsSDK = {
        let sdk = FastCommentsSDK(
            config: FastCommentsWidgetConfig(
                tenantId: "demo",
                urlId: "example-toolbar"
            )
        )

        // Apply a theme so toolbar buttons pick up the color
        sdk.theme = FastCommentsTheme.allPrimary(.indigo)

        return sdk
    }()

    var body: some View {
        // Pass custom buttons to the comments view
        // These appear in the formatting toolbar alongside bold/italic/code/link
        FastCommentsView(
            sdk: sdk,
            customToolbarButtons: [
                EmojiButton(),
                CodeBlockButton(),
            ]
        )
        .task {
            try? await sdk.load()
        }
        .navigationTitle("Custom Toolbar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Example Custom Buttons

/// Inserts a common emoji at the cursor.
struct EmojiButton: CustomToolbarButton {
    let id = "emoji"
    let iconSystemName = "face.smiling"
    let contentDescription = "Add Emoji"
    let badgeText: String? = nil

    func onClick(text: Binding<String>) {
        text.wrappedValue += "\u{1F44D}"
    }
}

/// Wraps text in a code block.
struct CodeBlockButton: CustomToolbarButton {
    let id = "code-block"
    let iconSystemName = "doc.text"
    let contentDescription = "Code Block"
    let badgeText: String? = nil

    func onClick(text: Binding<String>) {
        text.wrappedValue += "<pre><code></code></pre>"
    }
}
