import SwiftUI
import FastCommentsSwift

/// Renders a single feed post. Switches layout based on FeedPostType.
/// Mirrors FeedPostsAdapter.java view types from Android.
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
        VStack(alignment: .leading, spacing: 8) {
            // Header: avatar, name, date
            HStack(spacing: 8) {
                Button {
                    onUserClick?(.feedPost(post), UserInfo.from(post), .avatar)
                } label: {
                    AvatarImage(url: post.fromUserAvatar, size: 40)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        onUserClick?(.feedPost(post), UserInfo.from(post), .name)
                    } label: {
                        Text(post.fromUserDisplayName ?? "Anonymous")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)

                    Text(RelativeDateFormatter.format(post.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Delete menu (only for own posts)
                if post.fromUserId == sdk.currentUser?.id {
                    Menu {
                        Button(role: .destructive) { onDelete?(post) } label: {
                            Label(NSLocalizedString("delete", bundle: .module, comment: ""), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .padding(.horizontal, 12)

            // Content
            if let contentHTML = post.contentHTML, !contentHTML.isEmpty {
                HTMLContentView(html: contentHTML)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
            }

            // Media (based on post type)
            let postType = FeedPostType.determine(from: post)
            switch postType {
            case .singleImage:
                if let media = post.media, let item = media.first,
                   let asset = item.sizes.first, let url = URL(string: asset.src) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            #if os(iOS)
                            Rectangle().fill(Color(uiColor: .systemGray5))
                            #else
                            Rectangle().fill(Color(nsColor: .controlBackgroundColor))
                            #endif
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { onMediaClick?(item, 0) }
                }

            case .multiImage:
                if let media = post.media {
                    PostImagesCarousel(mediaItems: media, onImageTap: onMediaClick)
                }

            case .task:
                if let links = post.links {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            if let urlString = link.url, let url = URL(string: urlString) {
                                Link(destination: url) {
                                    HStack {
                                        Image(systemName: "link")
                                        Text(link.text ?? link.title ?? urlString)
                                            .lineLimit(1)
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(theme.resolveLinkColor())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

            case .textOnly:
                EmptyView()
            }

            // Action bar: comment, like, share
            HStack(spacing: 24) {
                Button { onComment?(post) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        if let count = post.commentCount, count > 0 {
                            Text("\(count)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    Task { try? await sdk.reactPost(postId: post.id) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sdk.hasUserReacted(postId: post.id, reactType: "like") ? "heart.fill" : "heart")
                            .foregroundStyle(sdk.hasUserReacted(postId: post.id, reactType: "like") ? .red : .secondary)
                        let count = sdk.getLikeCount(postId: post.id)
                        if count > 0 {
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)

                Button { onShare?(post) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .contentShape(Rectangle())
        .onTapGesture { onPostClick?(post) }
    }
}
