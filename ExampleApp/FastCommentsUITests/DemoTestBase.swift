import XCTest
import CommonCrypto

/// Base class for demo video UI tests. Provides slow typing, demo personas,
/// pause helpers, and feed post seeding on top of UITestBase.
class DemoTestBase: UITestBase {

    // MARK: - Personas

    enum DemoPersona: String, CaseIterable {
        case alice, bob, charlie, sarah

        var userId: String { "demo-\(rawValue)" }

        var displayName: String {
            switch self {
            case .alice:   return "Alice Chen"
            case .bob:     return "Bob Martinez"
            case .charlie: return "Charlie Park"
            case .sarah:   return "Sarah Kim"
            }
        }

        var email: String { "\(rawValue)@demo.fastcomments.com" }
        var avatarURL: String { "https://i.pravatar.cc/150?u=fc-\(rawValue)" }
    }

    // MARK: - Natural Typing

    /// Types text one character at a time with randomized delays for a natural feel.
    /// Average ~12 chars/sec, with longer pauses after punctuation.
    func typeCommentSlowly(_ text: String) {
        let input = app.textViews["comment-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Comment input should exist")
        input.tap()
        for char in text {
            input.typeText(String(char))
            let delay: UInt32 = ".,!?".contains(char) ? 200_000 : UInt32.random(in: 50_000...120_000)
            usleep(delay)
        }
    }

    /// Intentional pause so the viewer can absorb what happened.
    func pauseForViewer(_ seconds: Double = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Persona SSO

    /// Build a secure SSO token with persona-specific identity (name, email, avatar).
    func makePersonaToken(_ persona: DemoPersona, isAdmin: Bool = false) -> String {
        var userData: [String: Any] = [
            "id": persona.userId,
            "email": persona.email,
            "username": persona.displayName,
            "avatar": persona.avatarURL
        ]
        if isAdmin { userData["isAdmin"] = true }

        let userDataJSON = try! JSONSerialization.data(withJSONObject: userData)
        let userDataBase64 = userDataJSON.base64EncodedString()
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let message = "\(timestamp)\(userDataBase64)"

        let key = testTenantApiKey!.data(using: .utf8)!
        let messageData = message.data(using: .utf8)!
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBytes in
            messageData.withUnsafeBytes { msgBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.baseAddress, key.count,
                        msgBytes.baseAddress, messageData.count,
                        &hmac)
            }
        }
        let hash = hmac.map { String(format: "%02x", $0) }.joined()

        let payload: [String: Any] = [
            "userDataJSONBase64": userDataBase64,
            "verificationHash": hash,
            "timestamp": timestamp
        ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: payloadData, encoding: .utf8)!
    }

    // MARK: - Seeding

    /// Seed a comment via API with a specific persona identity and optional parentId for threading.
    /// Returns the comment ID (makes an extra API call to fetch it).
    @discardableResult
    func seedCommentAsPersona(urlId: String, persona: DemoPersona, text: String, parentId: String? = nil) -> String? {
        let ssoToken = makePersonaToken(persona)
        seedComment(urlId: urlId, text: text, ssoToken: ssoToken, parentId: parentId)
        usleep(200_000)
        return fetchLatestCommentId(urlId: urlId)
    }

    /// Seed a comment quickly without fetching its ID. Use for bulk seeding where
    /// you don't need to reference the comment later.
    func seedCommentFast(urlId: String, persona: DemoPersona, text: String) {
        let ssoToken = makePersonaToken(persona)
        seedComment(urlId: urlId, text: text, ssoToken: ssoToken)
    }

    /// Seed a feed post via HTTP API.
    func seedFeedPost(contentHTML: String, persona: DemoPersona, mediaURLs: [String] = []) {
        let ssoToken = makePersonaToken(persona)
        let encodedSSO = ssoToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://fastcomments.com/feed-posts/\(testTenantId!)?sso=\(encodedSSO)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "contentHTML": contentHTML
        ]

        if !mediaURLs.isEmpty {
            let media = mediaURLs.map { urlStr -> [String: Any] in
                return [
                    "sizes": [
                        ["w": 800, "h": 600, "src": urlStr]
                    ]
                ]
            }
            body["media"] = media
        }

        request.httpBody = try! JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
        sem.wait()

        usleep(300_000)
    }

    /// React to a feed post (like).
    func reactToFeedPost(postId: String, persona: DemoPersona) {
        let ssoToken = makePersonaToken(persona)
        let encodedSSO = ssoToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://fastcomments.com/feed-posts/\(testTenantId!)/react/\(postId)?sso=\(encodedSSO)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["reactType": "l"])

        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
        sem.wait()
    }

    // MARK: - App Launch Variants

    @discardableResult
    func launchChatApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-test-chat", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchFeedApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-test-feed", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchThemedApp(urlId: String, ssoToken: String, theme: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-test-theme", testTenantId, urlId, ssoToken, theme]
        application.launch()
        app = application
        return application
    }
}
