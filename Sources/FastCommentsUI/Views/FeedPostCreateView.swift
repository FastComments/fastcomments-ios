import SwiftUI
import PhotosUI
import FastCommentsSwift
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// View for creating a new feed post with text, images, and links.
/// Mirrors FeedPostCreateView.java from Android.
public struct FeedPostCreateView: View {
    @ObservedObject var sdk: FastCommentsFeedSDK
    var customToolbarButtons: [any FeedCustomToolbarButton] = []
    var onPostCreated: ((FeedPost) -> Void)?
    var onCancelled: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fastCommentsTheme) private var theme
    @State private var postContent: String = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var loadedImages: [UIImage] = []
    @State private var imageFileURLs: [URL] = []
    @State private var isPosting: Bool = false
    @State private var errorMessage: String?
    @State private var uploadProgress: Double = 0

    private let maxImages = 10

    public init(sdk: FastCommentsFeedSDK, customToolbarButtons: [any FeedCustomToolbarButton] = [],
                onPostCreated: ((FeedPost) -> Void)? = nil, onCancelled: (() -> Void)? = nil) {
        self.sdk = sdk
        self.customToolbarButtons = customToolbarButtons
        self.onPostCreated = onPostCreated
        self.onCancelled = onCancelled
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // User header
                        HStack(spacing: 8) {
                            AvatarImage(url: sdk.currentUser?.avatarSrc, size: 40)
                            Text(sdk.currentUser?.username ?? sdk.currentUser?.displayName ?? "Anonymous")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12)

                        // Text input
                        TextField(
                            NSLocalizedString("write_post_hint", bundle: .module, comment: ""),
                            text: $postContent,
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(3...20)
                        .padding(.horizontal, 12)

                        // Selected images
                        SelectedMediaGrid(selectedItems: $selectedItems, loadedImages: $loadedImages)

                        // Error
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                        }

                        // Upload progress
                        if isPosting && uploadProgress > 0 && uploadProgress < 1 {
                            ProgressView(value: uploadProgress)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.top, 12)
                }

                Divider()

                // Toolbar
                HStack {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: maxImages,
                        matching: .images
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3)
                            .foregroundStyle(
                                loadedImages.count >= maxImages ? .secondary : theme.resolveActionButtonColor()
                            )
                    }
                    .disabled(loadedImages.count >= maxImages)
                    .onChange(of: selectedItems) { newItems in
                        Task { await loadImages(newItems) }
                    }

                    // Custom toolbar buttons
                    ForEach(customToolbarButtons.filter { $0.isVisible() }, id: \.id) { button in
                        Button {
                            button.onClick(content: $postContent)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: button.iconSystemName)
                                    .font(.title3)
                                    .foregroundStyle(
                                        button.isEnabled() ? theme.resolveActionButtonColor() : .secondary
                                    )
                                if let badge = button.badgeText {
                                    Text(badge)
                                        .font(.system(size: 8))
                                        .padding(2)
                                        .background(Color.red)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!button.isEnabled())
                        .accessibilityLabel(button.contentDescription)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .navigationTitle(NSLocalizedString("create_post", bundle: .module, comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", bundle: .module, comment: "")) {
                        cleanupTempFiles()
                        onCancelled?()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submitPost() }
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text(NSLocalizedString("post", bundle: .module, comment: ""))
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isPosting || postContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Private

    private func loadImages(_ items: [PhotosPickerItem]) async {
        cleanupTempFiles()
        var images: [UIImage] = []
        var urls: [URL] = []
        for item in items {
            guard let file = try? await item.loadTransferable(type: ImageFileTransferable.self) else { continue }
            urls.append(file.url)
            if let thumb = generateThumbnail(from: file.url) {
                images.append(thumb)
            }
        }
        loadedImages = images
        imageFileURLs = urls
    }

    private func generateThumbnail(from url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 160,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func submitPost() async {
        isPosting = true
        errorMessage = nil
        defer {
            cleanupTempFiles()
            isPosting = false
        }

        do {
            // Upload images if any
            var mediaItems: [FeedPostMediaItem] = []
            if !imageFileURLs.isEmpty {
                let totalImages = Double(imageFileURLs.count)
                for (index, fileURL) in imageFileURLs.enumerated() {
                    let mediaItem = try await sdk.uploadImage(fileURL: fileURL)
                    mediaItems.append(mediaItem)
                    uploadProgress = Double(index + 1) / totalImages
                }
            }

            let params = CreateFeedPostParams(
                contentHTML: postContent,
                media: mediaItems.isEmpty ? nil : mediaItems,
                fromUserId: sdk.currentUser?.id,
                fromUserDisplayName: sdk.currentUser?.username ?? sdk.currentUser?.displayName
            )

            let post = try await sdk.createPost(params: params)
            onPostCreated?(post)
            dismiss()
        } catch let error as FastCommentsError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanupTempFiles() {
        for url in imageFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        imageFileURLs.removeAll()
    }
}
