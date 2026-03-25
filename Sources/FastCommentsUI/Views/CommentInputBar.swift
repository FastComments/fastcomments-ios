import SwiftUI
import FastCommentsSwift

/// Bottom comment input bar with reply indicator, formatting toolbar, and @mention support.
/// Mirrors BottomCommentInputView.java from Android.
public struct CommentInputBar: View {
    @ObservedObject var sdk: FastCommentsSDK
    @Binding var replyingTo: RenderableComment?
    var customToolbarButtons: [any CustomToolbarButton] = []
    var onCommentPosted: ((PublicComment) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var text: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    @State private var mentionSuggestions: [UserSearchResult] = []
    @State private var selectedMentions: [CommentUserMentionInfo] = []
    @FocusState private var isTextFieldFocused: Bool

    public var body: some View {
        VStack(spacing: 0) {
            // Mention suggestions overlay
            MentionSuggestionsList(suggestions: mentionSuggestions) { user in
                insertMention(user)
            }

            // Reply indicator
            if let replyingTo = replyingTo {
                HStack {
                    Text(String(
                        format: NSLocalizedString("replying_to_%@", bundle: .module, comment: ""),
                        replyingTo.comment.commenterName
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        self.replyingTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            Divider()

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                AvatarImage(url: sdk.currentUser?.avatarSrc, size: 28)

                TextField(
                    replyingTo != nil
                        ? NSLocalizedString("reply_hint", bundle: .module, comment: "")
                        : NSLocalizedString("comment_hint", bundle: .module, comment: ""),
                    text: $text,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.subheadline)
                .lineLimit(1...5)
                .focused($isTextFieldFocused)
                .onChange(of: text) { _, newValue in
                    handleTextChange(newValue)
                }

                Button {
                    Task { await submitComment() }
                } label: {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? .secondary
                                    : theme.resolveActionButtonColor()
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Private

    private func submitComment() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        errorMessage = nil

        do {
            let comment = try await sdk.postComment(
                text: trimmed,
                parentId: replyingTo?.comment.id,
                mentions: selectedMentions.isEmpty ? nil : selectedMentions
            )
            text = ""
            replyingTo = nil
            selectedMentions.removeAll()
            mentionSuggestions.removeAll()
            onCommentPosted?(comment)
        } catch let error as FastCommentsError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    private func handleTextChange(_ newText: String) {
        // Check for @mention trigger
        guard let lastAtIndex = newText.lastIndex(of: "@") else {
            mentionSuggestions = []
            return
        }

        let afterAt = newText[newText.index(after: lastAtIndex)...]
        let query = String(afterAt)

        // Only search if there's a query and no space after @
        guard !query.isEmpty, !query.contains(" ") else {
            mentionSuggestions = []
            return
        }

        Task {
            do {
                let results = try await sdk.searchUsers(query: query)
                mentionSuggestions = results
            } catch {
                mentionSuggestions = []
            }
        }
    }

    private func insertMention(_ user: UserSearchResult) {
        // Replace @query with @username
        if let lastAtIndex = text.lastIndex(of: "@") {
            let displayName = user.displayName ?? user.name
            text = String(text[..<lastAtIndex]) + "@\(displayName) "

            let mentionInfo = CommentUserMentionInfo(
                id: user.id,
                tag: "@\(displayName)"
            )
            selectedMentions.append(mentionInfo)
        }
        mentionSuggestions = []
    }
}
