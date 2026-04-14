import XCTest

/// Verifies the follow/unfollow pill on feed posts:
/// * renders only on posts authored by other users,
/// * flips optimistically on tap and then settles to confirmed state,
/// * and — critically — syncs across every visible post authored by the same
///   user, so following Sarah from post A also updates Sarah's post B.
final class FollowButtonUITests: UITestBase {

    override var stableTenantEmail: String { "ios-follow-ui@fctest.com" }

    func testFollow_updatesAllPostsForSameAuthor() {
        let urlId = "follow-\(Int(Date().timeIntervalSince1970))"
        let sarahToken = makeSecureSSOToken(userId: "sarah-\(Int(Date().timeIntervalSince1970))")
        let viewerToken = makeSecureSSOToken(userId: "viewer-\(Int(Date().timeIntervalSince1970))")

        // Seed two posts authored by Sarah so the viewer sees them as
        // other-user posts. Their ids drive the follow-button accessibility
        // identifiers on the client.
        let stamp = Int(Date().timeIntervalSince1970)
        let post1Text = "Sarah post 1 \(stamp)"
        let post2Text = "Sarah post 2 \(stamp)"
        guard let post1Id = seedFeedPost(urlId: urlId, text: post1Text, ssoToken: sarahToken) else {
            XCTFail("Failed to seed post 1"); return
        }
        guard let post2Id = seedFeedPost(urlId: urlId, text: post2Text, ssoToken: sarahToken) else {
            XCTFail("Failed to seed post 2"); return
        }

        // Launch the follow-test harness as the viewer (different user).
        launchFollowTestApp(urlId: urlId, ssoToken: viewerToken)

        let button1 = app.buttons["follow-button-\(post1Id)"]
        let button2 = app.buttons["follow-button-\(post2Id)"]

        XCTAssertTrue(button1.waitForExistence(timeout: 20), "Follow button should render on post 1")
        XCTAssertTrue(button2.waitForExistence(timeout: 20), "Follow button should render on post 2")

        // Initial state: both show "Follow".
        XCTAssertEqual(button1.label, "Follow", "Post 1 button should start as Follow")
        XCTAssertEqual(button2.label, "Follow", "Post 2 button should start as Follow")

        // Tap follow on post 1.
        button1.tap()

        // Optimistic: button 1 flips immediately. Button 2 may either still
        // show "Follow" (provider cache not yet updated) or may have already
        // updated if the render coalesced — either is acceptable pre-callback.
        XCTAssertTrue(
            waitForLabel(button1, "Following", timeout: 3),
            "Post 1 button should flip to Following optimistically"
        )

        // After the provider callback resolves (~500ms in the test harness),
        // the SDK's followStateRevision is bumped and EVERY visible button
        // for Sarah re-queries the provider. Both should now show Following.
        XCTAssertTrue(
            waitForLabel(button2, "Following", timeout: 5),
            "Post 2 button should update to Following after the provider confirms — this is the multi-post-sync behavior"
        )
        XCTAssertEqual(button1.label, "Following", "Post 1 button should settle on Following")

        // Unfollow from post 2 → both revert.
        button2.tap()

        XCTAssertTrue(
            waitForLabel(button2, "Follow", timeout: 3),
            "Post 2 button should flip back to Follow optimistically on unfollow"
        )
        XCTAssertTrue(
            waitForLabel(button1, "Follow", timeout: 5),
            "Post 1 button should also revert to Follow after the provider confirms unfollow"
        )
    }

    /// Same multi-post-sync scenario as above, but against a harness that
    /// mirrors the real `FeedExampleView` demo byte-for-byte: 3-second
    /// provider delay and the full modifier chain on `FastCommentsFeedView`.
    /// Proves the sync works under demo-equivalent conditions.
    func testFollow_demoParity_updatesAllPostsForSameAuthor() {
        let urlId = "follow-demo-\(Int(Date().timeIntervalSince1970))"
        let sarahToken = makeSecureSSOToken(userId: "sarah-\(Int(Date().timeIntervalSince1970))")
        let viewerToken = makeSecureSSOToken(userId: "viewer-\(Int(Date().timeIntervalSince1970))")

        let stamp = Int(Date().timeIntervalSince1970)
        let post1Text = "Sarah demo post 1 \(stamp)"
        let post2Text = "Sarah demo post 2 \(stamp)"
        guard let post1Id = seedFeedPost(urlId: urlId, text: post1Text, ssoToken: sarahToken) else {
            XCTFail("Failed to seed post 1"); return
        }
        guard let post2Id = seedFeedPost(urlId: urlId, text: post2Text, ssoToken: sarahToken) else {
            XCTFail("Failed to seed post 2"); return
        }

        launchFollowDemoTestApp(urlId: urlId, ssoToken: viewerToken)

        let button1 = app.buttons["follow-button-\(post1Id)"]
        let button2 = app.buttons["follow-button-\(post2Id)"]

        XCTAssertTrue(button1.waitForExistence(timeout: 20), "Follow button should render on post 1 (demo parity)")
        XCTAssertTrue(button2.waitForExistence(timeout: 20), "Follow button should render on post 2 (demo parity)")

        XCTAssertEqual(button1.label, "Follow")
        XCTAssertEqual(button2.label, "Follow")

        button1.tap()

        // Optimistic flip on tapped button — fast (sub-second).
        XCTAssertTrue(
            waitForLabel(button1, "Following", timeout: 3),
            "Post 1 should flip optimistically"
        )

        // Critical: post 2 must update after the 3-second provider callback.
        // Give it up to 8 seconds to cover the 3s sleep plus UI settling.
        XCTAssertTrue(
            waitForLabel(button2, "Following", timeout: 8),
            "Post 2 must flip to Following after the 3s provider callback — this exercises the invalidateFollowState broadcast path under demo conditions"
        )
    }

    /// Poll an element's accessibilityLabel until it matches `expected` or the
    /// timeout elapses. Returns `true` on success. (XCTNSPredicateExpectation
    /// against .label is awkward here because the value is re-read by the
    /// accessibility runtime on each query.)
    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.label == expected
    }
}
