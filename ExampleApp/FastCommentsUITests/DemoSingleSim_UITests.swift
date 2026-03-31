import XCTest

/// Single-simulator demo video segments.
/// Each test method is one segment, designed for visual appeal when recorded.
/// Pauses are minimal — just enough for the viewer to register what happened.
final class DemoSingleSim_UITests: DemoTestBase {

    // MARK: - Segment 1: Beautiful Comments

    func testSegment1_BeautifulComments() {
        let urlId = makeUrlId()
        let aliceSSO = makePersonaToken(.alice)

        // Seed root comments
        let charlieId = seedCommentAsPersona(
            urlId: urlId, persona: .charlie,
            text: "Just shipped the new analytics dashboard. The real-time charts are incredibly responsive!"
        )
        let sarahId = seedCommentAsPersona(
            urlId: urlId, persona: .sarah,
            text: "Love the dark mode support, works perfectly with our app's theme"
        )

        // Threaded replies
        if let cid = charlieId {
            let bobReplyId = seedCommentAsPersona(
                urlId: urlId, persona: .bob,
                text: "The charting library choice was spot on. Can we add export to PDF?",
                parentId: cid
            )
            if let bid = bobReplyId {
                seedCommentAsPersona(
                    urlId: urlId, persona: .charlie,
                    text: "Already on the roadmap for v2.1!",
                    parentId: bid
                )
            }
        }

        // Bulk comments for scroll density — fast, no ID fetch
        let bulkComments: [(DemoPersona, String)] = [
            (.bob, "Performance benchmarks look great — sub-100ms render time on all devices"),
            (.sarah, "The accessibility audit passed with flying colors"),
            (.charlie, "Pushed the latest localization strings for German and French"),
            (.bob, "CI pipeline is green across all targets"),
            (.sarah, "The onboarding flow conversion rate is up 12% this week"),
            (.charlie, "Memory profiling shows a 30% reduction after the latest refactor"),
            (.bob, "Design team approved the new comment card layout"),
            (.sarah, "WebSocket reconnection logic is much more robust now"),
            (.charlie, "The image carousel gesture handling feels really polished"),
            (.bob, "The mention autocomplete suggestions are lightning fast"),
        ]
        for (persona, text) in bulkComments {
            seedCommentFast(urlId: urlId, persona: persona, text: text)
        }
        usleep(500_000)

        // Launch and wait
        launchApp(urlId: urlId, ssoToken: aliceSSO)
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)
        pauseForViewer(0.8)

        // Smooth scroll to show density
        let scrollView = app.scrollViews["comments-scroll"]
        scrollView.swipeUp(velocity: .slow)
        pauseForViewer(0.3)
        scrollView.swipeUp(velocity: .slow)
        pauseForViewer(0.3)

        // Scroll back to top
        scrollView.swipeDown(velocity: .fast)
        scrollView.swipeDown(velocity: .fast)
        pauseForViewer(0.5)

        // Tap heart vote on Sarah's comment
        if let sid = sarahId {
            let heart = app.descendants(matching: .any)["vote-up-\(sid)"]
            if heart.waitForExistence(timeout: 5) {
                heart.tap()
                pauseForViewer(0.5)
            }
        }

        // Type a comment with @mention
        typeCommentSlowly("@Sarah")
        pauseForViewer(1.5) // Show autocomplete dropdown

        // Tap first mention suggestion
        let mentionSuggestion = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'mention-'")
        ).firstMatch
        if mentionSuggestion.waitForExistence(timeout: 5) {
            mentionSuggestion.tap()
        }

        // Continue typing
        let input = app.textViews["comment-input"]
        input.typeText(" love the dark mode support!")
        pauseForViewer(0.3)

        // Submit and brief wait
        app.buttons["comment-submit"].tap()
        pollUntil(timeout: 10) { self.app.staticTexts["love the dark mode support!"].exists }
        pauseForViewer(0.8)
    }

    // MARK: - Segment 2: Rich Interactions

    func testSegment2_RichInteractions() {
        let urlId = makeUrlId()
        let aliceAdminSSO = makeSecureSSOToken(userId: DemoPersona.alice.userId, isAdmin: true)

        // Seed comments
        let charlieId = seedCommentAsPersona(
            urlId: urlId, persona: .charlie,
            text: "The new component API is really clean and intuitive"
        )
        let sarahId = seedCommentAsPersona(
            urlId: urlId, persona: .sarah,
            text: "Agreed, the SwiftUI integration feels native"
        )
        if let cid = charlieId {
            seedCommentAsPersona(
                urlId: urlId, persona: .bob,
                text: "Love the modifier-based callbacks",
                parentId: cid
            )
            seedCommentAsPersona(
                urlId: urlId, persona: .sarah,
                text: "The theming system is really flexible too",
                parentId: cid
            )
        }

        // Launch as Alice (admin)
        launchApp(urlId: urlId, ssoToken: aliceAdminSSO)
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)
        pauseForViewer(0.5)

        // Tap reply on Charlie's comment
        if let cid = charlieId {
            let replyBtn = app.buttons["reply-\(cid)"]
            if replyBtn.waitForExistence(timeout: 5) {
                replyBtn.tap()
                pauseForViewer(0.3)
            }

            // Bold formatting
            let boldBtn = app.buttons["Bold"]
            if boldBtn.waitForExistence(timeout: 5) {
                boldBtn.tap()
            }
            typeCommentSlowly("Absolutely")
            if boldBtn.exists {
                boldBtn.tap()
            }

            let input = app.textViews["comment-input"]
            for char in " agree with this!" {
                input.typeText(String(char))
                usleep(UInt32.random(in: 50_000...120_000))
            }
            pauseForViewer(0.3)

            // Submit reply
            app.buttons["comment-submit"].tap()
            pauseForViewer(0.8)
        }

        // Pin Sarah's comment via admin API
        if let sid = sarahId {
            adminUpdateComment(commentId: sid, params: ["isPinned": true])
            app.terminate()
            launchApp(urlId: urlId, ssoToken: aliceAdminSSO)
            let pinIcon = app.descendants(matching: .any)["pin-icon-\(sid)"]
            _ = pinIcon.waitForExistence(timeout: 10)
            pauseForViewer(0.8)
        }

        // Toggle replies collapse/expand
        if let cid = charlieId {
            let toggle = app.buttons["toggle-replies-\(cid)"]
            if toggle.waitForExistence(timeout: 5) {
                toggle.tap() // collapse
                pauseForViewer(0.5)
                toggle.tap() // expand
                pauseForViewer(0.8)
            }
        }
    }

    // MARK: - Segment 4: Live Chat

    func testSegment4_LiveChat() {
        let urlId = makeUrlId()
        let aliceSSO = makePersonaToken(.alice)

        // Seed chat messages
        let chatMessages: [(DemoPersona, String)] = [
            (.charlie, "Good morning everyone!"),
            (.sarah, "Hey Charlie! Ready for the sprint review?"),
            (.bob, "Just finishing up the PR now"),
            (.charlie, "Sounds good, take your time"),
            (.sarah, "The new features are looking great in staging"),
        ]
        for (persona, text) in chatMessages {
            let sso = makePersonaToken(persona)
            seedComment(urlId: urlId, text: text, ssoToken: sso)
        }
        usleep(300_000)

        // Launch in chat mode
        launchChatApp(urlId: urlId, ssoToken: aliceSSO)
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)
        pauseForViewer(0.8)

        // Alice types
        typeCommentSlowly("Hey everyone, the deploy just finished!")
        pauseForViewer(0.2)
        app.buttons["comment-submit"].tap()
        pauseForViewer(0.5)

        // Live message from Bob
        let bobSSO = makePersonaToken(.bob)
        seedComment(urlId: urlId, text: "Nice, I see the metrics looking good already", ssoToken: bobSSO)
        pollUntil(timeout: 15) {
            self.app.staticTexts["Nice, I see the metrics looking good already"].exists
        }
        pauseForViewer(0.8)
    }

    // MARK: - Segment 5: Social Feed

    func testSegment5_SocialFeed() {
        let urlId = makeUrlId()
        let aliceSSO = makePersonaToken(.alice)

        // Seed feed posts
        seedFeedPost(
            contentHTML: "<p>Just wrapped up the Q1 roadmap review. Excited about the direction!</p>",
            persona: .charlie
        )
        seedFeedPost(
            contentHTML: "<p>New office views from the engineering floor</p>",
            persona: .sarah,
            mediaURLs: [
                "https://picsum.photos/seed/fc-demo1/800/600",
                "https://picsum.photos/seed/fc-demo2/800/600"
            ]
        )
        seedFeedPost(
            contentHTML: "<p>Shipped v3.2 — 47 bug fixes, 12 new features, zero regressions!</p>",
            persona: .bob
        )

        // Launch feed
        launchFeedApp(urlId: urlId, ssoToken: aliceSSO)
        pauseForViewer(2.0)

        // Scroll through
        let firstList = app.scrollViews.firstMatch
        firstList.swipeUp(velocity: .slow)
        pauseForViewer(0.8)
        firstList.swipeDown(velocity: .slow)
        pauseForViewer(0.8)
    }

    // MARK: - Segment 6: Theming

    func testSegment6a_ThemeFlat() {
        let urlId = makeUrlId()
        let aliceSSO = makePersonaToken(.alice)
        seedDemoComments(urlId: urlId)
        launchThemedApp(urlId: urlId, ssoToken: aliceSSO, theme: "flat")
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)
        pauseForViewer(2.0)
    }

    func testSegment6b_ThemeCard() {
        let urlId = makeUrlId()
        let aliceSSO = makePersonaToken(.alice)
        seedDemoComments(urlId: urlId)
        launchThemedApp(urlId: urlId, ssoToken: aliceSSO, theme: "card")
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)
        pauseForViewer(2.0)
    }

    func testSegment6c_ThemeBubble() {
        let urlId = makeUrlId()
        let aliceSSO = makePersonaToken(.alice)
        seedDemoComments(urlId: urlId)
        launchThemedApp(urlId: urlId, ssoToken: aliceSSO, theme: "bubble")
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)
        pauseForViewer(2.0)
    }

    // MARK: - Helpers

    private func seedDemoComments(urlId: String) {
        seedCommentAsPersona(urlId: urlId, persona: .charlie, text: "The new analytics dashboard looks amazing!")
        let sarahId = seedCommentAsPersona(urlId: urlId, persona: .sarah, text: "Love the dark mode support")
        seedCommentAsPersona(urlId: urlId, persona: .bob, text: "Performance benchmarks are impressive")
        if let sid = sarahId {
            seedCommentAsPersona(urlId: urlId, persona: .charlie, text: "Thanks! We put a lot of work into it", parentId: sid)
        }
    }
}
