import Foundation

/// Client-supplied hook that drives the follow/unfollow pill on feed posts.
///
/// `FastCommentsFeedSDK` does not persist follow state itself — it only renders
/// the UI. Register an implementation via
/// ``FastCommentsFeedSDK/followStateProvider`` to make the button visible on
/// posts authored by other users; when no provider is registered the button is
/// hidden entirely.
///
/// Mirrors `FollowStateProvider.java` in the Android SDK so host-app code paths
/// line up across platforms.
@MainActor
public protocol FollowStateProvider: AnyObject {

    /// Synchronously return the currently-known follow state for `user`.
    ///
    /// Called during view bind, so the implementation must be fast — back it
    /// with an in-memory cache. Return `false` if state is not yet known.
    func isFollowing(_ user: UserInfo) -> Bool

    /// Called when the viewer taps the follow/unfollow pill.
    ///
    /// The SDK applies an optimistic UI update immediately and then disables
    /// the button until `result` fires. The implementation **must** invoke
    /// `result` exactly once — on success, failure, or no-op — otherwise the
    /// button remains disabled. Pass the unchanged state to revert the
    /// optimistic update on failure.
    ///
    /// `result` is safe to call from any thread; the SDK marshals to the main
    /// actor internally before touching UI.
    ///
    /// - Parameters:
    ///   - user: the post author being followed / unfollowed.
    ///   - desiredFollowing: the requested new state (`true` = follow).
    ///   - result: invoked with the actual state after the change.
    func requestFollowStateChange(
        for user: UserInfo,
        desiredFollowing: Bool,
        result: @escaping @Sendable (Bool) -> Void
    )
}
