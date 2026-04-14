import SwiftUI
import FastCommentsSwift

/// Inline follow / unfollow link rendered next to the author name in a feed
/// post header.
///
/// The button is purely presentational — it defers all state (is-following
/// lookup, persistence, backend calls) to a ``FollowStateProvider`` registered
/// on the SDK. When no provider is registered, or when the visibility rules
/// fail, the view resolves to `EmptyView` and the header lays out as if it
/// weren't there.
///
/// Visibility rules (all must hold):
/// * a ``FollowStateProvider`` is registered on the SDK,
/// * the viewer is authenticated (`sdk.currentUser?.id` is non-nil),
/// * the post has a non-empty `fromUserId`,
/// * the viewer is not the post author.
public struct FollowButton: View {

    let post: FeedPost
    @ObservedObject var sdk: FastCommentsFeedSDK

    @Environment(\.fastCommentsTheme) private var theme
    @StateObject private var state = FollowButtonState()

    public init(post: FeedPost, sdk: FastCommentsFeedSDK) {
        self.post = post
        self.sdk = sdk
    }

    public var body: some View {
        if let provider = sdk.followStateProvider,
           Self.shouldShow(hasProvider: true, currentUserId: sdk.currentUser?.id, post: post) {
            let user = UserInfo.from(post)
            // `@ObservedObject var sdk` already subscribes this view to every
            // @Published on the SDK, including `followStateRevision` — no
            // explicit read is needed. Any call to `invalidateFollowState()`
            // invalidates this body, which then re-queries the provider.
            // Display state: optimistic override wins while a tap is in
            // flight; otherwise read the provider's current truth so buttons
            // for the same user on other posts stay in sync.
            let isFollowing = state.optimisticFollowing ?? provider.isFollowing(user)

            Button {
                state.tap(user: user, provider: provider, sdk: sdk)
            } label: {
                label(text: isFollowing, actionColor: theme.resolveActionButtonColor())
            }
            .buttonStyle(.plain)
            .disabled(state.isPending)
            .opacity(state.isPending ? 0.6 : 1.0)
            .accessibilityIdentifier("follow-button-\(post.id)")
            .modifier(ResetOnPostChange(postId: post.id, reset: state.reset))
        }
    }

    // MARK: - Label

    @ViewBuilder
    private func label(text isFollowing: Bool, actionColor: Color) -> some View {
        let title = isFollowing
            ? NSLocalizedString("following", bundle: .module, comment: "Follow button — already following")
            : NSLocalizedString("follow", bundle: .module, comment: "Follow button — not yet following")

        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(actionColor)
            .contentShape(Rectangle())
    }

    // MARK: - Visibility (testable pure function)

    /// Whether the follow button should render for the given inputs. Extracted
    /// as a pure function so it can be unit-tested without spinning up SwiftUI.
    static func shouldShow(hasProvider: Bool, currentUserId: String?, post: FeedPost) -> Bool {
        guard hasProvider else { return false }
        guard let currentUserId, !currentUserId.isEmpty else { return false }
        guard let postUserId = post.fromUserId, !postUserId.isEmpty else { return false }
        return currentUserId != postUserId
    }
}

/// Bridges SwiftUI's iOS-16 single-closure `onChange(of:_:)` and the iOS-17
/// two-closure variant — the old API emits a deprecation warning on 17+, the
/// new API doesn't exist on 16. Encapsulates the `if #available` so callers
/// stay readable.
private struct ResetOnPostChange: ViewModifier {
    let postId: String
    let reset: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.onChange(of: postId) { _, _ in reset() }
        } else {
            content.onChange(of: postId) { _ in reset() }
        }
    }
}

// MARK: - State

/// Controller for ``FollowButton``'s optimistic-update state machine.
///
/// Kept as a dedicated ObservableObject (rather than inline `@State`) so the
/// tap/callback/recycle flow is directly unit-testable.
@MainActor
final class FollowButtonState: ObservableObject {

    /// Non-nil while an optimistic tap is in flight. Overrides the provider's
    /// current truth for display purposes until the callback confirms.
    @Published private(set) var optimisticFollowing: Bool? = nil
    @Published private(set) var isPending: Bool = false

    /// Incremented on every post-id change. The tap handler captures the
    /// current value; late provider callbacks whose captured generation no
    /// longer matches are silently dropped. Prevents the previous post's
    /// follow state from being painted onto a reused row.
    private var bindGeneration: Int = 0

    /// Reset for a new post bound to the same view. Bumps the generation so
    /// any in-flight callback from the previous bind is discarded.
    func reset() {
        bindGeneration &+= 1
        optimisticFollowing = nil
        isPending = false
    }

    /// Tap handler: optimistic flip + disable, delegate to the provider, then
    /// broadcast via `sdk.invalidateFollowState()` so every visible button
    /// showing the same user re-queries the provider.
    func tap(user: UserInfo, provider: any FollowStateProvider, sdk: FastCommentsFeedSDK) {
        guard !isPending else { return }

        // Re-read from the provider so the toggle is based on truth, not on
        // a cached display value.
        let currently = provider.isFollowing(user)
        let desired = !currently

        optimisticFollowing = desired
        isPending = true
        let boundGeneration = bindGeneration

        provider.requestFollowStateChange(for: user, desiredFollowing: desired) { [weak self, weak sdk] _ in
            // Callback may fire on any thread; hop to main actor.
            Task { @MainActor [weak self, weak sdk] in
                guard let self else { return }
                // Drop stale callbacks from a previous bind.
                guard self.bindGeneration == boundGeneration else { return }
                // Clear the optimistic override — next render reads truth
                // from the provider (which the client updated before firing
                // the callback).
                self.optimisticFollowing = nil
                self.isPending = false
                // Broadcast to other visible buttons for the same user.
                sdk?.invalidateFollowState()
            }
        }
    }
}

