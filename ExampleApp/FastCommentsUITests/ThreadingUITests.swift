import XCTest

final class ThreadingUITests: UITestBase {

    override var stableTenantEmail: String { "ios-threading-ui@fctest.com" }

    func testReplyToComment() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)

        typeComment("Parent comment")

        guard let commentId = fetchLatestCommentId(urlId: urlId) else { return }

        let replyButton = app.buttons["reply-\(commentId)"]
        XCTAssertTrue(replyButton.waitForExistence(timeout: 5))
        replyButton.tap()

        typeComment("This is a reply")

        XCTAssertTrue(app.staticTexts["This is a reply"].waitForExistence(timeout: 10), "Reply should appear")
        XCTAssertTrue(app.staticTexts["Parent comment"].exists, "Parent comment should still exist")
    }

    // Known issue: With asTree + maxTreeDepth:1, replies may load inline.
    // The "Show N replies" toggle only appears when children aren't pre-loaded.
    // Tracked at: https://github.com/FastComments/fastcomments-ios/issues

    func testShowHideReplies() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        seedComment(urlId: urlId, text: "Parent with replies", ssoToken: sso)
        guard let parentId = fetchLatestCommentId(urlId: urlId) else { return }

        for i in 1...3 {
            let encodedSSO = sso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let sem = DispatchSemaphore(value: 0)
            let url = URL(string: "https://fastcomments.com/comments/\(testTenantId!)?broadcastId=\(UUID().uuidString)&urlId=\(urlId)&sso=\(encodedSSO)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "comment": "Reply \(i)", "commenterName": "Tester",
                "commenterEmail": "tester@fctest.com", "url": urlId,
                "urlId": urlId, "parentId": parentId
            ]
            request.httpBody = try! JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
            sem.wait()
        }

        launchApp(urlId: urlId, ssoToken: sso)
        XCTAssertTrue(app.staticTexts["Parent with replies"].waitForExistence(timeout: 10))

        let showReplies = app.buttons.matching(NSPredicate(format: "label CONTAINS 'replies'")).firstMatch
        XCTAssertTrue(
            showReplies.waitForExistence(timeout: 5),
            "Show replies toggle should exist (known issue: may not appear with maxTreeDepth:1)"
        )

        if showReplies.exists {
            showReplies.tap()
            XCTAssertTrue(app.staticTexts["Reply 1"].waitForExistence(timeout: 5))
        }
    }
}
