import SwiftUI

/// Sheet for editing a comment's text.
/// Mirrors CommentEditDialog.java from Android.
public struct CommentEditSheet: View {
    let currentText: String
    var onSave: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var editText: String = ""

    public init(currentText: String, onSave: ((String) -> Void)? = nil) {
        self.currentText = currentText
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $editText)
                    .font(.body)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                    .padding()

                Spacer()
            }
            .navigationTitle(NSLocalizedString("edit_comment", bundle: .module, comment: ""))
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // Strip HTML for editing
                editText = currentText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
        }
    }
}
