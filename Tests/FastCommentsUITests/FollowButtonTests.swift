import XCTest
import SwiftUI
import FastCommentsSwift
@testable import FastCommentsUI

@MainActor
final class FollowButtonTests: XCTestCase {

    // MARK: - Visibility predicate

    func testVisibility_hiddenWhenNoProvider() {
        let post = makePost(authorId: "author-1")
        XCTAssertFalse(FollowButton.shouldShow(hasProvider: false, currentUserId: "viewer-1", post: post))
    }

    func testVisibility_hiddenWhenAnonymousViewer() {
        let post = makePost(authorId: "author-1")
        XCTAssertFalse(FollowButton.shouldShow(hasProvider: true, currentUserId: nil, post: post))
        XCTAssertFalse(FollowButton.shouldShow(hasProvider: true, currentUserId: "", post: post))
    }

    func testVisibility_hiddenOnSelfPost() {
        let post = makePost(authorId: "viewer-1")
        XCTAssertFalse(FollowButton.shouldShow(hasProvider: true, currentUserId: "viewer-1", post: post))
    }

    func testVisibility_hiddenWhenPostHasNoAuthorId() {
        let post = makePost(authorId: nil)
        XCTAssertFalse(FollowButton.shouldShow(hasProvider: true, currentUserId: "viewer-1", post: post))

        let emptyAuthor = makePost(authorId: "")
        XCTAssertFalse(FollowButton.shouldShow(hasProvider: true, currentUserId: "viewer-1", post: emptyAuthor))
    }

    func testVisibility_shownWhenAllConditionsMet() {
        let post = makePost(authorId: "author-1")
        XCTAssertTrue(FollowButton.shouldShow(hasProvider: true, currentUserId: "viewer-1", post: post))
    }

    // MARK: - State machine

    func testTap_appliesOptimisticFollow_thenConfirms() async {
        let provider = FakeProvider(initialFollowing: false)
        let sdk = makeSDK()
        let state = FollowButtonState()

        state.tap(user: user(), provider: provider, sdk: sdk)

        // Optimistic: override set + disabled
        XCTAssertEqual(state.optimisticFollowing, true)
        XCTAssertTrue(state.isPending)
        XCTAssertEqual(provider.lastDesired, true)
        let revisionBefore = sdk.followStateRevision

        // Provider confirms (updates its own cache first)
        provider.followingUserIds.insert("author-1")
        provider.flushLastCallback(with: true)
        await waitForMainActor()

        // Optimistic cleared; provider is the source of truth now
        XCTAssertNil(state.optimisticFollowing)
        XCTAssertFalse(state.isPending)
        XCTAssertTrue(provider.isFollowing(user()))
        // SDK revision bumped so other buttons re-render
        XCTAssertEqual(sdk.followStateRevision, revisionBefore + 1)
    }

    func testTap_appliesOptimisticUnfollow_thenConfirms() async {
        let provider = FakeProvider(initialFollowing: true)
        let sdk = makeSDK()
        let state = FollowButtonState()

        state.tap(user: user(), provider: provider, sdk: sdk)

        XCTAssertEqual(state.optimisticFollowing, false)
        XCTAssertTrue(state.isPending)
        XCTAssertEqual(provider.lastDesired, false)

        provider.followingUserIds.remove("author-1")
        provider.flushLastCallback(with: false)
        await waitForMainActor()

        XCTAssertNil(state.optimisticFollowing)
        XCTAssertFalse(state.isPending)
        XCTAssertFalse(provider.isFollowing(user()))
    }

    func testTap_callbackWithUnchangedState_revertsOptimisticUI() async {
        let provider = FakeProvider(initialFollowing: false)
        let sdk = makeSDK()
        let state = FollowButtonState()

        state.tap(user: user(), provider: provider, sdk: sdk)

        XCTAssertEqual(state.optimisticFollowing, true) // optimistic flip
        XCTAssertTrue(state.isPending)

        // Provider failure: returns unchanged (still not following) — the
        // client's cache was NOT updated.
        provider.flushLastCallback(with: false)
        await waitForMainActor()

        // Optimistic cleared; next render reads provider's still-not-following
        // truth. The button's display naturally reverts.
        XCTAssertNil(state.optimisticFollowing)
        XCTAssertFalse(state.isPending)
        XCTAssertFalse(provider.isFollowing(user()))
    }

    func testTap_staleCallbackAfterReset_isDropped() async {
        let provider = FakeProvider(initialFollowing: false)
        let sdk = makeSDK()
        let state = FollowButtonState()

        // Tap on post A (author-1)
        state.tap(user: userA(), provider: provider, sdk: sdk)
        XCTAssertEqual(state.optimisticFollowing, true)
        XCTAssertTrue(state.isPending)

        // View is reused for post B before the callback fires.
        state.reset()

        XCTAssertNil(state.optimisticFollowing) // no stale optimistic flip
        XCTAssertFalse(state.isPending)

        // Late callback from the author-1 request arrives — must be ignored.
        provider.flushLastCallback(with: true)
        await waitForMainActor()

        XCTAssertNil(state.optimisticFollowing) // undisturbed
        XCTAssertFalse(state.isPending)
    }

    func testTap_reEntrantTapWhilePendingIsIgnored() async {
        let provider = FakeProvider(initialFollowing: false)
        let sdk = makeSDK()
        let state = FollowButtonState()

        state.tap(user: user(), provider: provider, sdk: sdk)
        let firstDesired = provider.lastDesired
        let callbacksBefore = provider.pendingCallbacks.count

        // Second tap while pending — should be a no-op (button is disabled
        // in the view, but guard belt-and-braces in the state machine).
        state.tap(user: user(), provider: provider, sdk: sdk)

        XCTAssertEqual(provider.lastDesired, firstDesired)
        XCTAssertEqual(provider.pendingCallbacks.count, callbacksBefore)
    }

    func testInvalidateFollowState_bumpsRevision() {
        let sdk = makeSDK()
        let before = sdk.followStateRevision
        sdk.invalidateFollowState()
        sdk.invalidateFollowState()
        XCTAssertEqual(sdk.followStateRevision, before + 2)
    }

    // MARK: - Fixtures

    private func user() -> UserInfo {
        UserInfo(userId: "author-1", userName: "Alice", userAvatarUrl: nil)
    }

    private func userA() -> UserInfo { user() }

    private func userB() -> UserInfo {
        UserInfo(userId: "author-2", userName: "Bob", userAvatarUrl: nil)
    }

    private func makePost(authorId: String?) -> FeedPost {
        FeedPost(
            id: "post-1",
            tenantId: "tenant-1",
            fromUserId: authorId,
            createdAt: Date()
        )
    }

    private func makeSDK() -> FastCommentsFeedSDK {
        FastCommentsFeedSDK(config: FastCommentsWidgetConfig(tenantId: "tenant-1", urlId: "url-1"))
    }

    /// Yield so `Task { @MainActor in ... }` continuations scheduled inside
    /// the provider callback have a chance to run before assertions.
    private func waitForMainActor() async {
        await Task.yield()
        await Task.yield()
    }
}

// MARK: - Fake provider

@MainActor
private final class FakeProvider: FollowStateProvider {
    var followingUserIds: Set<String> = []
    private(set) var lastDesired: Bool?
    private(set) var pendingCallbacks: [(Bool) -> Void] = []

    init(initialFollowing: Bool) {
        if initialFollowing {
            followingUserIds.insert("author-1")
        }
    }

    func isFollowing(_ user: UserInfo) -> Bool {
        guard let id = user.userId else { return false }
        return followingUserIds.contains(id)
    }

    func requestFollowStateChange(
        for user: UserInfo,
        desiredFollowing: Bool,
        result: @escaping @Sendable (Bool) -> Void
    ) {
        lastDesired = desiredFollowing
        pendingCallbacks.append(result)
    }

    /// Fire the most recently captured callback with the supplied state,
    /// simulating the provider completing its backend round-trip.
    func flushLastCallback(with nowFollowing: Bool) {
        guard let cb = pendingCallbacks.popLast() else { return }
        cb(nowFollowing)
    }
}
