# FastCommentsUI

A native SwiftUI library for adding threaded comments, social feeds, and live chat to iOS and macOS apps. Built on the [FastComments](https://fastcomments.com) platform with real-time updates, SSO authentication, moderation tools, and comprehensive theming.

## Features

- Threaded comment trees with nested replies and pagination
- Social feed with post creation, reactions, and media attachments
- Live chat mode with auto-scroll and date separators
- Real-time updates via WebSocket (new comments, votes, presence)
- Single Sign-On (Simple SSO for testing, Secure SSO for production)
- Rich text editing with bold, italic, code, and @mentions
- Voting with configurable styles (up/down arrows or hearts)
- Moderation actions: flag, pin, lock, block
- Comprehensive theming with presets and full customization
- Custom toolbar buttons for comments and feed post creation
- Image uploads
- EU region support
- User presence (online/offline indicators)
- Tag-based feed filtering
- Localization support

## Requirements

- iOS 16+ or macOS 14+
- Swift 5.9+
- SwiftUI

## Installation

Add FastCommentsUI to your project using Swift Package Manager.

In Xcode: **File > Add Package Dependencies**, then enter the repository URL.

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fastcomments/fastcomments-ios.git", from: "1.0.0")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "FastCommentsUI", package: "fastcomments-ios")
    ]
)
```

Import both modules where needed:

```swift
import FastCommentsUI
import FastCommentsSwift
```

## Quick Start

The minimum setup to display a comment widget:

```swift
import SwiftUI
import FastCommentsUI

struct ContentView: View {
    @StateObject private var sdk = FastCommentsSDK(
        config: FastCommentsWidgetConfig(
            tenantId: "demo",
            urlId: "my-page-1",
            url: "https://example.com/page-1",
            pageTitle: "My Page"
        )
    )

    var body: some View {
        FastCommentsView(sdk: sdk)
            .task {
                try? await sdk.load()
            }
    }
}
```

Replace `"demo"` with your FastComments tenant ID. The `urlId` identifies the page or thread where comments are stored.

---

## Authentication (SSO)

FastComments supports three authentication modes:

1. **Anonymous** -- no SSO token; users get session-based identities
2. **Simple SSO** -- client-side token for demos and testing (not secure)
3. **Secure SSO** -- server-signed token for production

### Simple SSO

Useful for demos and local testing. Anyone can impersonate any user with Simple SSO, so do not use it in production.

```swift
import FastCommentsSwift

let userData = SimpleSSOUserData(
    username: "Jane Doe",
    email: "jane@example.com",
    avatar: "https://example.com/avatar.jpg"
)
let sso = FastCommentsSSO.createSimple(simpleSSOUserData: userData)
let token = try? sso.prepareToSend()

let config = FastCommentsWidgetConfig(
    tenantId: "YOUR_TENANT_ID",
    urlId: "my-page-1",
    sso: token
)
let sdk = FastCommentsSDK(config: config)
```

`SimpleSSOUserData` also supports optional fields:

- `id` -- user ID (defaults to email if not set)
- `displayName` -- separate display name
- `displayLabel` -- custom label shown next to the name (e.g. "VIP")
- `websiteUrl` -- link on the user's name
- `locale` -- locale code
- `isProfileActivityPrivate` -- hide profile activity (defaults to true)

### Secure SSO

In production, your backend generates a signed SSO token using your API secret. The iOS app fetches this token from your server and passes it to the config.

**On your backend** (using the FastComments Swift SDK or any language):

```swift
let userData = SecureSSOUserData(
    id: "user-123",
    email: "user@example.com",
    username: "Display Name",
    avatar: "https://example.com/avatar.jpg"
)
let sso = try FastCommentsSSO.createSecure(apiKey: "YOUR_API_KEY", secureSSOUserData: userData)
let token = try sso.prepareToSend()
// Return this token to your iOS app via your API
```

**In your iOS app:**

```swift
struct MyView: View {
    @StateObject private var sdk = FastCommentsSDK(
        config: FastCommentsWidgetConfig(
            tenantId: "YOUR_TENANT_ID",
            urlId: "my-page-1"
        )
    )
    @State private var isLoadingToken = true

    var body: some View {
        Group {
            if isLoadingToken {
                ProgressView("Loading...")
            } else {
                FastCommentsView(sdk: sdk)
            }
        }
        .task {
            // Fetch the token from your backend
            let token = try? await fetchSSOTokenFromYourBackend()
            // Create a new config with the token, or set it before load
            isLoadingToken = false
            try? await sdk.load()
        }
    }
}
```

`SecureSSOUserData` supports additional fields:

- `optedInNotifications` -- email notification opt-in
- `displayLabel` -- custom label
- `displayName` -- display name
- `websiteUrl` -- website URL
- `groupIds` -- group memberships
- `isAdmin` -- admin privileges
- `isModerator` -- moderator privileges
- `isProfileActivityPrivate` -- profile privacy

---

## Threaded Comments

### Basic Usage

```swift
struct CommentsPage: View {
    @StateObject private var sdk = FastCommentsSDK(
        config: FastCommentsWidgetConfig(
            tenantId: "YOUR_TENANT_ID",
            urlId: "article-42",
            url: "https://example.com/article/42",
            pageTitle: "Article Title"
        )
    )

    var body: some View {
        FastCommentsView(sdk: sdk)
            .task {
                try? await sdk.load()
            }
    }
}
```

### Vote Styles

The default vote style shows up/down arrows. Pass `._1` for heart-style votes:

```swift
FastCommentsView(sdk: sdk, voteStyle: ._1)
```

| Style | Appearance |
|-------|------------|
| `._0` | Up/down arrow buttons with net count |
| `._1` | Single heart button with count |

### Event Callbacks

Use modifier-style callbacks to handle user interactions:

```swift
FastCommentsView(sdk: sdk)
    .onCommentPosted { comment in
        print("New comment: \(comment.commentHTML)")
    }
    .onReplyClick { renderableComment in
        print("Replying to: \(renderableComment.comment.id)")
    }
    .onUserClick { context, userInfo, source in
        // source is .name or .avatar
        print("Tapped \(userInfo.displayName)")
    }
```

### Applying a Theme

Pass a theme through the SwiftUI environment:

```swift
FastCommentsView(sdk: sdk)
    .fastCommentsTheme(myTheme)
    .task { try? await sdk.load() }
```

Or set it directly on the SDK:

```swift
sdk.theme = FastCommentsTheme.modern
```

### Sort Direction

```swift
sdk.defaultSortDirection = .nf  // Newest first (default)
sdk.defaultSortDirection = .of  // Oldest first
sdk.defaultSortDirection = .mr  // Most relevant
```

---

## Live Chat

`LiveChatView` provides a real-time chat experience with auto-scroll, date separators, and a compact layout. It automatically configures the SDK for oldest-first sort and immediate live display.

```swift
struct ChatView: View {
    @StateObject private var sdk: FastCommentsSDK = {
        let config = FastCommentsWidgetConfig(
            tenantId: "YOUR_TENANT_ID",
            urlId: "chat-room-1",
            sso: ssoToken  // SSO recommended so users have names
        )
        return FastCommentsSDK(config: config)
    }()

    var body: some View {
        LiveChatView(sdk: sdk)
            .onCommentPosted { comment in
                print("Sent: \(comment.commentHTML)")
            }
            .task {
                try? await sdk.load()
            }
    }
}
```

`LiveChatView` supports these callbacks:

- `.onCommentPosted` -- fired when the user sends a message
- `.onCommentDeleted` -- fired when a message is deleted
- `.onUserClick` -- fired when a user's name or avatar is tapped

---

## Social Feed

The feed system is a separate SDK (`FastCommentsFeedSDK`) with its own view.

### Loading and Displaying the Feed

```swift
struct FeedPage: View {
    @StateObject private var sdk: FastCommentsFeedSDK = {
        let config = FastCommentsWidgetConfig(
            tenantId: "YOUR_TENANT_ID",
            urlId: "my-feed",
            sso: ssoToken
        )
        return FastCommentsFeedSDK(config: config)
    }()

    @State private var commentsPost: FeedPost?

    var body: some View {
        FastCommentsFeedView(sdk: sdk)
            .onPostSelected { post in
                commentsPost = post
            }
            .onCommentsRequested { post in
                commentsPost = post
            }
            .onSharePost { post in
                // Present share sheet
            }
            .onUserClick { context, userInfo, source in
                // Navigate to user profile
            }
            .onMediaClick { mediaItem, index in
                // Present full-screen image viewer
            }
            .task {
                try? await sdk.load()
            }
    }
}
```

The feed view includes pull-to-refresh and infinite scroll automatically.

### Creating Posts

Use `FeedPostCreateView` to present a post creation form:

```swift
@State private var showCreatePost = false

// In your view body:
.sheet(isPresented: $showCreatePost) {
    FeedPostCreateView(
        sdk: sdk,
        onPostCreated: { post in
            showCreatePost = false
            Task { try? await sdk.refresh() }
        },
        onCancelled: {
            showCreatePost = false
        }
    )
}
```

### Reacting to Posts

The SDK handles reactions with optimistic updates:

```swift
try await sdk.reactPost(postId: post.id, reactionType: "l")

// Check reaction state
let hasLiked = sdk.hasUserReacted(postId: post.id, reactType: "l")
let likeCount = sdk.getLikeCount(postId: post.id)
```

### Opening Comments on a Post

Use `CommentsSheet` to display comments for a feed post. It creates a `FastCommentsSDK` instance internally using the feed SDK's config:

```swift
.sheet(item: $commentsPost) { post in
    CommentsSheet(post: post, feedSDK: sdk, onUserClick: { context, userInfo, source in
        // Handle user click
    })
}
```

Note: `FeedPost` must conform to `Identifiable` for `.sheet(item:)`. Add this extension:

```swift
extension FeedPost: @retroactive Identifiable {}
```

### Tag-Based Feed Filtering

Implement the `TagSupplier` protocol to filter feed posts by tags:

```swift
struct TeamTagSupplier: TagSupplier {
    func getTags(currentUser: UserSessionInfo?) -> [String]? {
        guard let user = currentUser else { return nil }
        return ["team:\(user.id ?? "")", "public"]
    }
}

sdk.tagSupplier = TeamTagSupplier()
```

Return `nil` for an unfiltered global feed.

### Saving and Restoring Feed State

Preserve pagination state across view lifecycle events:

```swift
let state = sdk.savePaginationState()
// Later...
sdk.restorePaginationState(state)
```

### Deleting Posts

```swift
sdk.onPostDeleted = { postId in
    print("Post \(postId) was deleted")
}
```

---

## Theming

### Theme Presets

Four built-in presets are available:

```swift
// System defaults
sdk.theme = FastCommentsTheme.default

// Cards with shadows and large rounded corners
sdk.theme = FastCommentsTheme.modern

// Flat, no shadows, small corner radius, no thread lines
sdk.theme = FastCommentsTheme.minimal

// Set all action colors to a single brand color
sdk.theme = FastCommentsTheme.allPrimary(.indigo)
```

### Comment Display Styles

```swift
var theme = FastCommentsTheme()
theme.commentStyle = .flat    // Flat list with dividers (default)
theme.commentStyle = .card    // Rounded cards with shadows
theme.commentStyle = .bubble  // Chat bubble style
```

### Colors

All color properties are optional. Unset values fall back to sensible system defaults.

```swift
var theme = FastCommentsTheme()

// Brand colors
theme.primaryColor = .indigo
theme.primaryLightColor = .indigo.opacity(0.6)
theme.primaryDarkColor = Color(red: 0.2, green: 0.1, blue: 0.5)

// Backgrounds
theme.commentBackgroundColor = Color(.secondarySystemGroupedBackground)
theme.containerBackgroundColor = Color(.systemGroupedBackground)

// Action buttons
theme.actionButtonColor = .indigo
theme.replyButtonColor = .indigo
theme.toggleRepliesButtonColor = .indigo.opacity(0.8)
theme.loadMoreButtonTextColor = .indigo

// Votes
theme.voteActiveColor = .red
theme.voteCountColor = .primary
theme.voteCountZeroColor = .secondary
theme.voteDividerColor = Color(.separator)

// Links
theme.linkColor = .indigo
theme.linkColorPressed = .indigo.opacity(0.5)

// Dialogs
theme.dialogHeaderBackgroundColor = .indigo
theme.dialogHeaderTextColor = .white

// Input bar
theme.inputBarBackgroundColor = Color(.systemBackground)
theme.inputBarBorderColor = Color(.separator)

// Other
theme.onlineIndicatorColor = .green
theme.separatorColor = Color(.separator)
theme.badgeBackgroundColor = .gray.opacity(0.2)
theme.threadLineColor = .indigo.opacity(0.15)
```

### Typography

```swift
theme.commenterNameFont = .subheadline.weight(.bold)
theme.bodyFont = .body
theme.captionFont = .caption
theme.actionFont = .caption.weight(.medium)
```

### Layout and Spacing

```swift
theme.cornerRadius = .large       // .none, .small, .medium, .large
theme.commentSpacing = 4          // Points between comment rows
theme.nestingIndent = 20          // Points of indentation per nesting level
theme.avatarSize = 36             // Avatar diameter for root comments
theme.replyAvatarSize = 28        // Avatar diameter for nested replies
```

### Visual Effects

```swift
theme.showShadows = true          // Subtle shadows on cards
theme.showThreadLine = true       // Vertical line connecting nested replies
theme.animateVotes = true         // Spring animation on vote changes
```

### Applying Themes

Two approaches:

```swift
// Via SwiftUI environment (recommended for view hierarchy)
FastCommentsView(sdk: sdk)
    .fastCommentsTheme(theme)

// Directly on the SDK
sdk.theme = theme
```

---

## Custom Toolbar Buttons

### Comment Toolbar Buttons

Implement the `CustomToolbarButton` protocol to add buttons to the comment input toolbar:

```swift
struct EmojiButton: CustomToolbarButton {
    let id = "emoji"
    let iconSystemName = "face.smiling"       // SF Symbol name
    let contentDescription = "Add Emoji"
    let badgeText: String? = nil              // Optional badge count

    func onClick(text: Binding<String>) {
        text.wrappedValue += "\u{1F44D}"
    }

    // Optional overrides (default to true)
    func isEnabled() -> Bool { true }
    func isVisible() -> Bool { true }
}
```

Pass custom buttons when creating the view:

```swift
FastCommentsView(
    sdk: sdk,
    customToolbarButtons: [EmojiButton(), CodeBlockButton()]
)
```

Or add them globally on the SDK (applies to all instances):

```swift
sdk.addGlobalCustomToolbarButton(EmojiButton())
sdk.removeGlobalCustomToolbarButton(id: "emoji")
sdk.clearGlobalCustomToolbarButtons()
```

### Feed Toolbar Buttons

Implement `FeedCustomToolbarButton` for the post creation form:

```swift
struct HashtagButton: FeedCustomToolbarButton {
    let id = "hashtag"
    let iconSystemName = "number"
    let contentDescription = "Add Hashtag"

    func onClick(content: Binding<String>) {
        content.wrappedValue += "#"
    }
}
```

Pass them to the creation view:

```swift
FeedPostCreateView(
    sdk: sdk,
    customToolbarButtons: [HashtagButton()],
    onPostCreated: { _ in },
    onCancelled: { }
)
```

Or set them globally on the feed SDK:

```swift
sdk.globalFeedToolbarButtons = [HashtagButton()]
```

---

## Moderation

### Actions Available to All Users

- **Flag/Unflag** -- report a comment for review

```swift
try await sdk.flagComment(commentId: commentId)
try await sdk.unflagComment(commentId: commentId)
```

- **Block/Unblock** -- hide all comments from a user (per-viewer)

```swift
try await sdk.blockUser(commentId: commentId)
try await sdk.unblockUser(commentId: commentId)
```

### Admin-Only Actions

- **Pin/Unpin** -- pin a comment to the top of the thread

```swift
try await sdk.pinComment(commentId: commentId)
try await sdk.unpinComment(commentId: commentId)
```

- **Lock/Unlock** -- prevent new replies on a comment

```swift
try await sdk.lockComment(commentId: commentId)
try await sdk.unlockComment(commentId: commentId)
```

All moderation actions are also available through the comment context menu in the UI. Admin actions only appear when the current user is a site admin (set via SSO `isAdmin` flag or dashboard configuration).

---

## Real-Time Updates

After calling `sdk.load()`, the SDK automatically subscribes to WebSocket events for the configured `urlId`. The following events are handled:

- New comments, edits, and deletions
- Votes (new and removed)
- Pin, lock, flag, and block state changes
- User presence (join/leave)
- Thread open/close
- Badge awards
- Server configuration updates

### Controlling Live Display

By default, new comments from other users appear immediately:

```swift
sdk.showLiveRightAway = true   // Default: show instantly
```

Set this to `false` to buffer new comments behind a "N new comments" button, letting the user choose when to reveal them:

```swift
sdk.showLiveRightAway = false
```

### User Presence

Online/offline indicators appear automatically on user avatars when the server enables presence tracking. No additional configuration is needed on the client.

---

## Pagination

### Page Size

```swift
// Comments: default 30
sdk.pageSize = 50

// Feed: default 10
feedSDK.pageSize = 20
```

### Loading More Comments

The UI shows pagination controls automatically. You can also trigger pagination programmatically:

```swift
// Load next page
try await sdk.loadMore()

// Load all remaining (disabled if >2000 comments for performance)
try await sdk.loadAll()

// Check state
sdk.hasMore            // Whether more pages exist
sdk.shouldShowLoadAll()
sdk.getCountRemainingToShow()
```

### Child Comment Pagination

Nested replies load lazily. When a user expands a thread, the first 5 children load. A "load more replies" control appears if more exist. This is handled automatically by the UI.

---

## State and Observability

Both `FastCommentsSDK` and `FastCommentsFeedSDK` are `ObservableObject` classes with `@Published` properties. You can observe these in your SwiftUI views for reactive UI updates.

### FastCommentsSDK Published Properties

| Property | Type | Description |
|----------|------|-------------|
| `commentCountOnServer` | `Int` | Total comment count on the server |
| `newRootCommentCount` | `Int` | Buffered new comments (when `showLiveRightAway` is false) |
| `currentUser` | `UserSessionInfo?` | Current authenticated user |
| `isSiteAdmin` | `Bool` | Whether the current user is a site admin |
| `isClosed` | `Bool` | Whether the comment thread is closed |
| `hasBillingIssue` | `Bool` | Whether there is a billing problem |
| `isLoading` | `Bool` | Whether a network request is in progress |
| `hasMore` | `Bool` | Whether more pages of comments exist |
| `blockingErrorMessage` | `String?` | Error that prevents the UI from functioning |
| `warningMessage` | `String?` | Non-blocking warning message |
| `isDemo` | `Bool` | Whether running in demo mode |
| `commentsVisible` | `Bool` | Toggle for comment visibility |
| `toolbarEnabled` | `Bool` | Whether the formatting toolbar is shown |

### FastCommentsFeedSDK Published Properties

| Property | Type | Description |
|----------|------|-------------|
| `feedPosts` | `[FeedPost]` | Currently loaded feed posts |
| `hasMore` | `Bool` | Whether more pages exist |
| `currentUser` | `UserSessionInfo?` | Current authenticated user |
| `blockingErrorMessage` | `String?` | Blocking error message |
| `isLoading` | `Bool` | Whether a network request is in progress |
| `newPostsCount` | `Int` | Number of new posts since last load |

### Comment Tree

The comment tree is accessible via `sdk.commentsTree`:

```swift
// Flat list of visible nodes for rendering
sdk.commentsTree.visibleNodes

// Lookup a comment by ID
sdk.commentsTree.commentsById["comment-id"]
```

---

## EU Region

To use the EU data center, set the `region` field in your config:

```swift
let config = FastCommentsWidgetConfig(
    tenantId: "YOUR_TENANT_ID",
    urlId: "my-page",
    region: "eu"
)
```

This routes all API requests and WebSocket connections to `eu.fastcomments.com`.

---

## Cleanup

When you are done with an SDK instance (e.g., the view is being dismissed), call `cleanup()` to close the WebSocket connection and cancel background tasks:

```swift
sdk.cleanup()
```

For views managed by SwiftUI's `@StateObject`, this is typically called in `.onDisappear` or when the view is deallocated.

---

## Image Uploads

### Comments

```swift
let imageUrl = try await sdk.uploadImage(imageData: jpegData, filename: "photo.jpg")
```

Returns the URL string of the uploaded image.

### Feed Posts

```swift
let mediaItem = try await feedSDK.uploadImage(imageData: jpegData, filename: "photo.jpg")

// Upload multiple images in parallel
let mediaItems = try await feedSDK.uploadImages(images: [
    (jpegData1, "photo1.jpg"),
    (jpegData2, "photo2.jpg")
])
```

---

## User Mentions

Search for users to support @mention autocomplete:

```swift
let results = try await sdk.searchUsers(query: "jan")
// Returns [UserSearchResult] with userId, username, avatar, etc.
```

The built-in `CommentInputBar` handles @mention autocomplete automatically.

---

## Editing and Deleting Comments

### Edit

```swift
try await sdk.editComment(commentId: commentId, newText: "Updated text")
```

The server re-renders the HTML. The local comment updates automatically.

### Delete

```swift
try await sdk.deleteComment(commentId: commentId)
```

Deleting a comment also removes its descendants from the local tree.

Both actions are available through the comment context menu in the UI when the current user is the comment author (or a site admin).

---

## Error Handling

SDK methods throw `FastCommentsError`, which conforms to `LocalizedError`:

```swift
do {
    try await sdk.load()
} catch let error as FastCommentsError {
    print(error.translatedError ?? error.reason ?? "Unknown error")
} catch {
    print(error.localizedDescription)
}
```

`FastCommentsError` properties:

- `code` -- error code from the API
- `reason` -- English error description
- `translatedError` -- server-provided localized error message

Blocking errors are also surfaced automatically via `sdk.blockingErrorMessage`, which the built-in views display to the user.

---

## Localization

Pass a locale code in the config to localize server-provided strings:

```swift
let config = FastCommentsWidgetConfig(
    tenantId: "YOUR_TENANT_ID",
    urlId: "my-page",
    locale: "fr_fr"
)
```

Client-side UI strings use iOS bundle-based localization.

---

## Example App

The repository includes a full example app at `ExampleApp/` with demonstrations of:

- Threaded comments with SSO and custom themes
- Social feed with post creation and tag filtering
- Live chat
- Simple and Secure SSO flows
- Custom toolbar buttons (comments and feed)

## License

See [LICENSE](LICENSE) for details.
