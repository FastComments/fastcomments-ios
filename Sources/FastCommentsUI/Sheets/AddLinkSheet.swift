import SwiftUI

/// Sheet for adding a link to a comment or post.
/// Mirrors AddLinkDialog.java from Android.
public struct AddLinkSheet: View {
    var onLinkAdded: ((String, String) -> Void)?  // (url, label)

    @Environment(\.dismiss) private var dismiss
    @State private var url: String = ""
    @State private var label: String = ""

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("URL", text: $url)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField(NSLocalizedString("link_label", bundle: .module, comment: ""), text: $label)
                }
            }
            .navigationTitle(NSLocalizedString("add_link", bundle: .module, comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", bundle: .module, comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("add", bundle: .module, comment: "")) {
                        onLinkAdded?(url, label.isEmpty ? url : label)
                        dismiss()
                    }
                    .disabled(url.isEmpty)
                }
            }
        }
    }
}
