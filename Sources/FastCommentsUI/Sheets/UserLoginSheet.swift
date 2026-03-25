import SwiftUI

/// Login credentials sheet for anonymous users.
/// Mirrors UserLoginDialog.java from Android.
public struct UserLoginSheet: View {
    public enum LoginAction: Sendable {
        case vote
        case comment
    }

    let action: LoginAction
    var onCredentialsEntered: ((String, String) -> Void)?  // (name, email)
    var onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var email: String = ""

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NSLocalizedString("name", bundle: .module, comment: ""), text: $name)
                        .textContentType(.name)
                    TextField(NSLocalizedString("email", bundle: .module, comment: ""), text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(action == .vote
                         ? NSLocalizedString("login_to_vote", bundle: .module, comment: "")
                         : NSLocalizedString("login_to_comment", bundle: .module, comment: "")
                    )
                }
            }
            .navigationTitle(NSLocalizedString("login", bundle: .module, comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", bundle: .module, comment: "")) {
                        onCancel?()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("submit", bundle: .module, comment: "")) {
                        onCredentialsEntered?(name, email)
                        dismiss()
                    }
                    .disabled(name.isEmpty || email.isEmpty)
                }
            }
        }
    }
}
