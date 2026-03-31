import SwiftUI
import PhotosUI
import FastCommentsSwift
#if canImport(UIKit)
import UIKit
#endif

/// Bottom comment input bar with WYSIWYG formatting, reply indicator, and @mention support.
public struct CommentInputBar: View {
    @ObservedObject var sdk: FastCommentsSDK
    @Binding var replyingTo: RenderableComment?
    var customToolbarButtons: [any CustomToolbarButton] = []
    var onCommentPosted: ((PublicComment) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    #if os(iOS)
    @State private var attributedText = NSAttributedString()
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var isEditorFocused = false
    @StateObject private var editorContext = RichTextEditorContext()
    #else
    @State private var text: String = ""
    #endif
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    @State private var mentionSuggestions: [UserSearchResult] = []
    @State private var selectedMentions: [CommentUserMentionInfo] = []
    @State private var showAddLinkSheet: Bool = false
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage: Bool = false
    #endif

    private var isEmpty: Bool {
        #if os(iOS)
        attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #else
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #endif
    }

    private var plainText: String {
        #if os(iOS)
        attributedText.string
        #else
        text
        #endif
    }

    /// Merges global SDK toolbar buttons with per-instance buttons, de-duplicated by ID.
    private var mergedCustomButtons: [any CustomToolbarButton] {
        var buttons = sdk.globalCustomToolbarButtons
        for button in customToolbarButtons {
            if !buttons.contains(where: { $0.id == button.id }) {
                buttons.append(button)
            }
        }
        return buttons
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Mention suggestions overlay
            MentionSuggestionsList(suggestions: mentionSuggestions) { user in
                insertMention(user)
            }

            // Reply indicator
            if let replyingTo = replyingTo {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.resolveActionButtonColor())
                        .frame(width: 3, height: 20)

                    Text(String(
                        format: NSLocalizedString("replying_to_%@", bundle: .module, comment: ""),
                        replyingTo.comment.commenterName
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.resolveActionButtonColor())
                    .lineLimit(1)

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.replyingTo = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Error message
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                    Text(error)
                        .font(.caption2)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
            }

            // Formatting toolbar
            if !sdk.disableToolbar && sdk.toolbarEnabled {
                Divider()
                    .opacity(0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        if sdk.defaultFormattingButtonsEnabled {
                            #if os(iOS)
                            toolbarButton(icon: "bold", accessibilityKey: "format_bold") {
                                editorContext.toggleBold()
                            }
                            toolbarButton(icon: "italic", accessibilityKey: "format_italic") {
                                editorContext.toggleItalic()
                            }
                            toolbarButton(icon: "strikethrough", accessibilityKey: "format_strikethrough") {
                                editorContext.toggleStrikethrough()
                            }
                            Button {
                                editorContext.toggleCode()
                            } label: {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(theme.resolveActionButtonColor())
                                    .frame(width: 36, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(NSLocalizedString("format_code", bundle: .module, comment: ""))
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        editorContext.toggleCodeBlock()
                                    }
                            )
                            toolbarButton(icon: "link", accessibilityKey: "add_link") {
                                showAddLinkSheet = true
                            }

                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images
                            ) {
                                if isUploadingImage {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 36, height: 30)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(theme.resolveActionButtonColor())
                                        .frame(width: 36, height: 30)
                                }
                            }
                            .disabled(isUploadingImage)
                            .onChange(of: selectedPhotoItem) { newItem in
                                guard let newItem else { return }
                                Task { await handleImagePicked(newItem) }
                                selectedPhotoItem = nil
                            }
                            #else
                            toolbarButton(icon: "bold", accessibilityKey: "format_bold") {
                                text += "<b></b>"
                            }
                            toolbarButton(icon: "italic", accessibilityKey: "format_italic") {
                                text += "<i></i>"
                            }
                            toolbarButton(icon: "link", accessibilityKey: "add_link") {
                                showAddLinkSheet = true
                            }
                            #endif
                        }

                        // Custom toolbar buttons (global + per-instance, de-duped)
                        ForEach(mergedCustomButtons.filter { $0.isVisible() }, id: \.id) { button in
                            Button {
                                button.onClick(text: plainTextBinding)
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: button.iconSystemName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(
                                            button.isEnabled() ? theme.resolveActionButtonColor() : .secondary
                                        )
                                        .frame(width: 36, height: 30)
                                    if let badge = button.badgeText {
                                        Text(badge)
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(2)
                                            .background(Color.red)
                                            .foregroundStyle(.white)
                                            .clipShape(Circle())
                                            .offset(x: 4, y: -2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!button.isEnabled())
                            .accessibilityLabel(button.contentDescription)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                #if os(iOS)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
                #else
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                #endif
            }

            Divider()
                .opacity(0.5)

            // Input row
            HStack(alignment: .bottom, spacing: 10) {
                AvatarImage(url: sdk.currentUser?.avatarSrc, size: 30)

                #if os(iOS)
                ZStack(alignment: .leading) {
                    if attributedText.length == 0 && !isEditorFocused {
                        Text(replyingTo != nil
                             ? NSLocalizedString("reply_hint", bundle: .module, comment: "")
                             : NSLocalizedString("comment_hint", bundle: .module, comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    RichTextEditor(
                        attributedText: $attributedText,
                        selectedRange: $selectedRange,
                        isFocused: $isEditorFocused,
                        context: editorContext
                    )
                    .frame(minHeight: 36)
                    .accessibilityIdentifier("comment-input")
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(inputFieldBackground)
                )
                #else
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
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(inputFieldBackground)
                )
                .onChange(of: text) { newValue in
                    handleTextChange(newValue)
                }
                #endif

                Button {
                    Task { await submitComment() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(isEmpty ? .secondary : theme.resolveActionButtonColor())
                                .rotationEffect(.degrees(isEmpty ? 0 : -45))
                                .animation(.spring(duration: 0.3), value: isEmpty)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isEmpty ? Color.clear : theme.resolveActionButtonColor().opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSending || isEmpty)
                .accessibilityIdentifier("comment-submit")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(theme.resolveInputBarBackgroundColor())
        #if os(iOS)
        .onAppear {
            editorContext.onPlainTextChange = { newText in
                handleTextChange(newText)
            }
        }
        #endif
        .sheet(isPresented: $showAddLinkSheet) {
            #if os(iOS)
            AddLinkSheet { url, label in
                if let linkURL = URL(string: url) {
                    editorContext.applyLink(url: linkURL, label: label)
                }
            }
            #else
            AddLinkSheet { url, label in
                let linkHtml = label.isEmpty
                    ? "<a href=\"\(url)\">\(url)</a>"
                    : "<a href=\"\(url)\">\(label)</a>"
                text += linkHtml
            }
            #endif
        }
    }

    // MARK: - Toolbar Button

    private func toolbarButton(icon: String, accessibilityKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.resolveActionButtonColor())
                .frame(width: 36, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString(accessibilityKey, bundle: .module, comment: ""))
    }

    // MARK: - Custom Toolbar Button Binding (backward compat)

    /// Computed Binding<String> for custom toolbar buttons that still operate on strings.
    private var plainTextBinding: Binding<String> {
        #if os(iOS)
        Binding(
            get: { attributedText.string },
            set: { newValue in
                let oldValue = attributedText.string
                guard newValue != oldValue else { return }

                let defaultAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.label
                ]

                if newValue.hasPrefix(oldValue) {
                    // Pure append
                    let appended = String(newValue.dropFirst(oldValue.count))
                    let mutable = NSMutableAttributedString(attributedString: attributedText)
                    mutable.append(NSAttributedString(string: appended, attributes: defaultAttrs))
                    attributedText = mutable
                } else {
                    // Full replacement or complex edit
                    attributedText = NSAttributedString(string: newValue, attributes: defaultAttrs)
                }
            }
        )
        #else
        $text
        #endif
    }

    // MARK: - Helpers

    private var inputFieldBackground: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemFill)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    // MARK: - Error Handling

    private static func friendlyErrorMessage(from error: Error) -> String {
        #if os(iOS)
        if case let ErrorResponse.error(_, data, _, _) = error, let data = data {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let translated = json["translatedError"] as? String, !translated.isEmpty {
                    return translated
                }
                if let reason = json["reason"] as? String, !reason.isEmpty {
                    return reason
                }
            }
        }
        #endif
        return NSLocalizedString("comment_post_failed", bundle: .module, comment: "")
    }

    // MARK: - Image Upload

    #if os(iOS)
    private func handleImagePicked(_ item: PhotosPickerItem) async {
        isUploadingImage = true
        defer { isUploadingImage = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let filename = "image_\(UUID().uuidString.prefix(8)).jpg"

            // Convert to JPEG if needed
            guard let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.8) else { return }

            let imageUrl = try await sdk.uploadImage(imageData: jpegData, filename: filename)

            // Insert image into the editor
            let imgTag = "<img src=\"\(imageUrl)\" />"
            let mutable = NSMutableAttributedString(attributedString: attributedText)

            // Create an image attachment for WYSIWYG display
            let thumbWidth: CGFloat = 150
            let thumbHeight = thumbWidth * image.size.height / image.size.width
            let attachment = NSTextAttachment()
            attachment.image = image.preparingThumbnail(of: CGSize(width: thumbWidth, height: thumbHeight)) ?? image
            attachment.bounds = CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight)

            let attachmentString = NSMutableAttributedString(attachment: attachment)
            // Store the URL so the HTML converter can find it
            attachmentString.addAttribute(.link, value: URL(string: imageUrl)!, range: NSRange(location: 0, length: attachmentString.length))
            attachmentString.addAttribute(.imageURL, value: imageUrl, range: NSRange(location: 0, length: attachmentString.length))

            mutable.append(NSAttributedString(string: "\n"))
            mutable.append(attachmentString)
            mutable.append(NSAttributedString(string: "\n", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.label
            ]))
            attributedText = mutable
        } catch {
            errorMessage = Self.friendlyErrorMessage(from: error)
        }
    }
    #endif

    // MARK: - Submit

    private func submitComment() async {
        guard !isEmpty else { return }

        isSending = true
        errorMessage = nil

        #if os(iOS)
        let htmlText = AttributedStringHTMLConverter.convert(attributedText)
        #else
        let htmlText = text
        #endif

        do {
            let comment = try await sdk.postComment(
                text: htmlText,
                parentId: replyingTo?.comment.id,
                mentions: selectedMentions.isEmpty ? nil : selectedMentions
            )
            #if os(iOS)
            attributedText = NSAttributedString()
            // Reset typing attributes to plain style
            editorContext.textView?.typingAttributes = [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.label
            ]
            #else
            text = ""
            #endif
            replyingTo = nil
            selectedMentions.removeAll()
            mentionSuggestions.removeAll()
            onCommentPosted?(comment)
        } catch let error as FastCommentsError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = Self.friendlyErrorMessage(from: error)
        }

        isSending = false
    }

    // MARK: - Mentions

    private func handleTextChange(_ newText: String) {
        guard let lastAtIndex = newText.lastIndex(of: "@") else {
            mentionSuggestions = []
            return
        }

        let afterAt = newText[newText.index(after: lastAtIndex)...]
        let query = String(afterAt)

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
        let displayName = user.displayName ?? user.name

        #if os(iOS)
        let currentText = attributedText.string
        guard let lastAtIndex = currentText.lastIndex(of: "@") else { return }

        let atPosition = currentText.distance(from: currentText.startIndex, to: lastAtIndex)
        let replaceRange = NSRange(location: atPosition, length: currentText.count - atPosition)

        let mentionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .subheadline).withTraits(.traitBold),
            .foregroundColor: UIColor.tintColor,
            .mentionUserId: user.id
        ]
        let mentionText = NSAttributedString(string: "@\(displayName) ", attributes: mentionAttrs)

        let mutable = NSMutableAttributedString(attributedString: attributedText)
        mutable.replaceCharacters(in: replaceRange, with: mentionText)
        attributedText = mutable
        #else
        guard let lastAtIndex = text.lastIndex(of: "@") else { return }
        text = String(text[..<lastAtIndex]) + "@\(displayName) "
        #endif

        let mentionInfo = CommentUserMentionInfo(
            id: user.id,
            tag: "@\(displayName)"
        )
        selectedMentions.append(mentionInfo)
        mentionSuggestions = []
    }
}

// MARK: - UIFont helper

#if canImport(UIKit)
private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
