import XCTest
import CommonCrypto

/// Alice (left simulator, observer role) for Segment 3: Live Real-Time Sync.
/// Runs on Simulator A. Coordinates with DemoUserB via SyncClient.
final class DemoUserA_UITests: DemoTestBase {

    override func setUpWithError() throws {
        SyncClient.currentRole = "userA"
        continueAfterFailure = true
        try super.setUpWithError()
    }

    func testSegment3_LiveSync() {
        let urlId = "demo-live-\(Int(Date().timeIntervalSince1970))"
        let ssoTokenA = makePersonaToken(.alice)
        let ssoTokenBAdmin = makePersonaToken(.bob, isAdmin: true)

        // Share config with UserB
        SyncClient.postData(round: "setup", data: [
            "tenantId": testTenantId!,
            "apiKey": testTenantApiKey!,
            "urlId": urlId,
            "ssoTokenBAdmin": ssoTokenBAdmin,
        ])

        // Seed some comments for visual context
        seedCommentAsPersona(urlId: urlId, persona: .charlie,
                             text: "The new analytics dashboard looks amazing!")
        let sarahId = seedCommentAsPersona(urlId: urlId, persona: .sarah,
                                           text: "Love the dark mode support, works perfectly with our theme")

        SyncClient.signalReady(round: "setup")

        // Launch as Alice
        launchApp(urlId: urlId, ssoToken: ssoTokenA)
        _ = app.textViews["comment-input"].waitForExistence(timeout: 15)
        pauseForViewer(0.5)

        // --- PHASE 1: Bob posts a comment (observe it appear live) ---
        SyncClient.signalReady(round: "phase1")
        SyncClient.waitFor(role: "userB", round: "phase1")

        let phase1Data = SyncClient.getData(round: "phase1")
        let bobCommentText = phase1Data["text"] as? String ?? "?"

        pollUntil(timeout: 15) { self.app.staticTexts[bobCommentText].exists }
        pauseForViewer(0.8)

        // --- PHASE 2: Alice upvotes a comment ---
        if let sid = sarahId {
            let voteUp = app.descendants(matching: .any)["vote-up-\(sid)"]
            if voteUp.waitForExistence(timeout: 5) {
                SyncClient.postData(round: "phase2_setup", data: ["commentId": sid])
                SyncClient.signalReady(round: "phase2")
                voteUp.tap()
                pauseForViewer(0.8)
                SyncClient.signalReady(round: "phase2_done")
            }
        }

        // --- PHASE 3: Bob pins a comment ---
        SyncClient.signalReady(round: "phase3")
        SyncClient.waitFor(role: "userB", round: "phase3")

        let phase3Data = SyncClient.getData(round: "phase3")
        let pinnedId = phase3Data["commentId"] as? String ?? ""

        let pinIcon = app.descendants(matching: .any)["pin-icon-\(pinnedId)"]
        _ = pinIcon.waitForExistence(timeout: 15)
        pauseForViewer(0.8)

        // --- PHASE 4: Alice types a comment with @mention ---
        typeCommentSlowly("@Bob")
        pauseForViewer(1.2) // Show autocomplete

        let mentionSuggestion = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'mention-'")
        ).firstMatch
        if mentionSuggestion.waitForExistence(timeout: 5) {
            mentionSuggestion.tap()
        }

        let input = app.textViews["comment-input"]
        for char in " looks good, shipping it!" {
            input.typeText(String(char))
            usleep(UInt32.random(in: 50_000...120_000))
        }

        app.buttons["comment-submit"].tap()
        pollUntil(timeout: 10) { self.app.staticTexts["looks good, shipping it!"].exists }

        SyncClient.postData(round: "phase4", data: ["text": "looks good, shipping it!"])
        SyncClient.signalReady(round: "phase4")
        pauseForViewer(1.0)

        SyncClient.signalReady(round: "done")
    }
}
