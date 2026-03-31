import XCTest

final class ThreadingUITests: UITestBase {

    func testReplyToComment() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()
        launchApp(urlId: urlId, ssoToken: sso)
        sleep(2)

        typeComment("Parent comment")

        guard let commentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch comment ID")
            return
        }

        // Tap reply button
        let replyButton = app.buttons["reply-\(commentId)"]
        XCTAssertTrue(replyButton.waitForExistence(timeout: 5))
        replyButton.tap()

        // Type reply
        typeComment("This is a reply")

        // Verify reply appears
        let replyText = app.staticTexts["This is a reply"]
        XCTAssertTrue(replyText.waitForExistence(timeout: 10), "Reply should appear")

        // Parent should still exist
        XCTAssertTrue(app.staticTexts["Parent comment"].exists, "Parent comment should still exist")
    }

    // TODO: With maxTreeDepth:1 and asTree, replies load inline — no "show replies" button
    func _skip_testShowHideReplies() {
        let urlId = makeUrlId()
        let sso = makeSecureSSOToken()

        // Seed parent + replies via API for speed
        seedComment(urlId: urlId, text: "Parent with replies", ssoToken: sso)

        guard let parentId = fetchLatestCommentId(urlId: urlId) else {
            XCTFail("Could not fetch parent ID")
            return
        }

        // Seed replies by posting via API with parentId
        let encodedSSO = sso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        for i in 1...3 {
            let done = expectation(description: "reply-\(i)")
            let url = URL(string: "https://fastcomments.com/comments/\(testTenantId!)?broadcastId=\(UUID().uuidString)&urlId=\(urlId)&sso=\(encodedSSO)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "comment": "Reply \(i)",
                "commenterName": "Tester",
                "commenterEmail": "tester@fctest.com",
                "url": urlId,
                "urlId": urlId,
                "parentId": parentId
            ]
            request.httpBody = try! JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
            wait(for: [done], timeout: 10)
        }

        launchApp(urlId: urlId, ssoToken: sso)

        // Parent should be visible
        XCTAssertTrue(
            app.staticTexts["Parent with replies"].waitForExistence(timeout: 10)
        )

        // Look for "Show 3 replies" button
        let showReplies = app.buttons.matching(NSPredicate(format: "label CONTAINS 'replies'")).firstMatch
        XCTAssertTrue(showReplies.waitForExistence(timeout: 5), "Show replies button should exist")
        showReplies.tap()

        // Replies should appear
        XCTAssertTrue(app.staticTexts["Reply 1"].waitForExistence(timeout: 5))
    }
}
