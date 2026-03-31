import SwiftUI

/// Sheet for editing a comment's text.
public struct CommentEditSheet: View {
    let currentText: String
    var onSave: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fastCommentsTheme) private var theme
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    public init(currentText: String, onSave: ((String) -> Void)? = nil) {
        self.currentText = currentText
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editText)
                    .font(.body)
                    .focused($isFocused)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("edit-comment-input")
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(editorBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? theme.resolveActionButtonColor().opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
                    .padding()

                Spacer()
            }
            .navigationTitle(NSLocalizedString("edit_comment", bundle: .module, comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", bundle: .module, comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", bundle: .module, comment: "")) {
                        onSave?(editText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("edit-comment-save")
                }
            }
            .onAppear {
                editText = currentText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                isFocused = true
            }
        }
    }

    private var editorBackground: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemFill)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
