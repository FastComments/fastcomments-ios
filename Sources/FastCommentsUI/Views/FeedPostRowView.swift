import SwiftUI
import FastCommentsSwift

/// Renders a single feed post with header, content, media, and action bar.
public struct FeedPostRowView: View {
    let post: FeedPost
    @ObservedObject var sdk: FastCommentsFeedSDK

    var onComment: ((FeedPost) -> Void)?
    var onLike: ((FeedPost) -> Void)?
    var onShare: ((FeedPost) -> Void)?
    var onPostClick: ((FeedPost) -> Void)?
    var onMediaClick: ((FeedPostMediaItem, Int) -> Void)?
    var onUserClick: ((UserClickContext, UserInfo, UserClickSource) -> Void)?
    var onDelete: ((FeedPost) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: avatar, name, date
            HStack(spacing: 10) {
                Button {
                    onUserClick?(.feedPost(post), UserInfo.from(post), .avatar)
                } label: {
                    AvatarImage(url: post.fromUserAvatar, size: 42)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        onUserClick?(.feedPost(post), UserInfo.from(post), .name)
                    } label: {
                        Text(post.fromUserDisplayName ?? "Anonymous")
                            .font(theme.resolveCommenterNameFont())
                    }
                    .buttonStyle(.plain)

                    Text(RelativeDateFormatter.format(post.createdAt))
                        .font(theme.resolveCaptionFont())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Delete menu
                if post.fromUserId == sdk.currentUser?.id {
                    Menu {
                        Button(role: .destructive) { onDelete?(post) } label: {
                            Label(NSLocalizedString("delete", bundle: .module, comment: ""), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.tertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 14)

            // Content
            if let contentHTML = post.contentHTML, !contentHTML.isEmpty {
                HTMLContentView(html: contentHTML)
                    .font(theme.resolveBodyFont())
                    .padding(.horizontal, 14)
            }

            // Media
            let postType = FeedPostType.determine(from: post)
            switch postType {
            case .singleImage:
                if let media = post.media, let item = media.first,
                   let asset = item.sizes.first, let url = URL(string: asset.src) {
                    SmartImage(url: url, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius.inner))
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                        .onTapGesture { onMediaClick?(item, 0) }
                }

            case .multiImage:
                if let media = post.media {
                    PostImagesCarousel(mediaItems: media, onImageTap: onMediaClick)
                }

            case .task:
                if let links = post.links {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            if let urlString = link.url, let url = URL(string: urlString) {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                            .font(.caption)
                                        Text(link.text ?? link.title ?? urlString)
                                            .lineLimit(1)
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(theme.resolveLinkColor())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(theme.resolveLinkColor().opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }

            case .textOnly:
                EmptyView()
            }

            // Action bar
            HStack(spacing: 0) {
                actionButton(icon: "bubble.right", count: post.commentCount) {
                    onComment?(post)
                }

                actionButton(
                    icon: sdk.hasUserReacted(postId: post.id, reactType: "like") ? "heart.fill" : "heart",
                    count: sdk.getLikeCount(postId: post.id) > 0 ? sdk.getLikeCount(postId: post.id) : nil,
                    tint: sdk.hasUserReacted(postId: post.id, reactType: "like") ? .red : nil
                ) {
                    Task { try? await sdk.reactPost(postId: post.id) }
                }

                actionButton(icon: "square.and.arrow.up") {
                    onShare?(post)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .padding(.top, 14)
        .contentShape(Rectangle())
        .onTapGesture { onPostClick?(post) }
    }

    // MARK: - Action Button

    private func actionButton(icon: String, count: Int? = nil, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tint ?? .secondary)
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var imagePlaceholder: some View {
        Rectangle()
            #if os(iOS)
            .fill(Color(uiColor: .systemGray6))
            #else
            .fill(Color(nsColor: .quaternaryLabelColor))
            #endif
            .overlay(
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
            )
    }
}
