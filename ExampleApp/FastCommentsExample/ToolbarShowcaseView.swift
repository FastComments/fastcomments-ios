import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Custom toolbar buttons in the comment input bar.
///
/// Shows how to:
/// - Enable/disable the toolbar and default formatting buttons via SDK
/// - Register global custom toolbar buttons at the SDK level
/// - Pass per-instance custom buttons to a specific view
/// - Implement the CustomToolbarButton protocol
struct ToolbarShowcaseView: View {
    @StateObject private var sdk: FastCommentsSDK = {
        let sdk = FastCommentsSDK(
            config: FastCommentsWidgetConfig(
                tenantId: "demo",
                urlId: "test"
            )
        )

        // Apply a theme so toolbar buttons pick up the color
        sdk.theme = FastCommentsTheme.allPrimary(.indigo)

        // 1. Enable the toolbar and default formatting buttons
        sdk.setCommentToolbarEnabled(true)
        sdk.setDefaultFormattingButtonsEnabled(true)

        // 2. Register global custom buttons — these appear on ALL comment inputs
        sdk.addGlobalCustomToolbarButton(EmojiButton())

        return sdk
    }()

    var body: some View {
        VStack {
            // 3. Per-instance buttons are passed here — merged with global buttons
            FastCommentsView(
                sdk: sdk,
                customToolbarButtons: [
                    CodeBlockButton(),
                ]
            )

            // 4. Demonstrate removing a global button at runtime
            HStack {
                Button("Remove Emoji") {
                    sdk.removeGlobalCustomToolbarButton(id: "emoji")
                }
                .buttonStyle(.bordered)

                Button("Add Emoji") {
                    sdk.addGlobalCustomToolbarButton(EmojiButton())
                }
                .buttonStyle(.bordered)

                Button("Clear All") {
                    sdk.clearGlobalCustomToolbarButtons()
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
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
