import XCTest
import CommonCrypto

/// UI tests that launch the ExampleApp with test data and verify rendered elements.
final class PaginationUITests: XCTestCase {

    private var testTenantId: String?
    private var testTenantEmail: String?
    private var testTenantApiKey: String?

    private let host = "https://fastcomments.com"
    private let e2eApiKey = "T0ph B3st"

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        let suffix = UUID().uuidString.prefix(8)
        let email = "ios-uitest-\(suffix)@fctest.com"
        testTenantEmail = email

        // Sign up tenant
        let signupDone = expectation(description: "signup")
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpShouldSetCookies = true
        let session = URLSession(configuration: sessionConfig)

        let signupURL = URL(string: "\(host)/auth/tenant-signup")!
        var signupRequest = URLRequest(url: signupURL)
        signupRequest.httpMethod = "POST"
        signupRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        signupRequest.httpBody = "username=uitest-\(suffix)&email=\(email)&companyName=UITest+\(suffix)&domains=uitest-\(suffix).example.com&packageId=adv&noTracking=true".data(using: .utf8)

        session.dataTask(with: signupRequest) { _, _, _ in signupDone.fulfill() }.resume()
        wait(for: [signupDone], timeout: 15)

        // Get tenant ID
        let tenantDone = expectation(description: "tenant")
        let encodedKey = e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let tenantURL = URL(string: "\(host)/test-e2e/api/tenant/by-email/\(email)?API_KEY=\(encodedKey)")!
        URLSession.shared.dataTask(with: tenantURL) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tenant = json["tenant"] as? [String: Any] {
                self.testTenantId = tenant["_id"] as? String
            }
            tenantDone.fulfill()
        }.resume()
        wait(for: [tenantDone], timeout: 15)
        XCTAssertNotNil(testTenantId, "Should have tenant ID")

        // Get API key
        let apiKeyDone = expectation(description: "apikey")
        let apiSecretURL = URL(string: "\(host)/auth/my-account/api-secret")!
        session.dataTask(with: apiSecretURL) { data, _, _ in
            if let data = data, let html = String(data: data, encoding: .utf8),
               let range = html.range(of: #"value="([A-Z0-9]+)""#, options: .regularExpression) {
                let match = String(html[range])
                self.testTenantApiKey = String(match.dropFirst(7).dropLast(1))
            }
            apiKeyDone.fulfill()
        }.resume()
        wait(for: [apiKeyDone], timeout: 15)
        XCTAssertNotNil(testTenantApiKey, "Should have API key")
    }

    override func tearDownWithError() throws {
        if let email = testTenantEmail {
            let done = expectation(description: "cleanup")
            let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            let encodedKey = e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let url = URL(string: "\(host)/test-e2e/api/tenant/by-email/\(encodedEmail)?API_KEY=\(encodedKey)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
            wait(for: [done], timeout: 15)
        }
    }

    // MARK: - Helpers

    private func makeSecureSSOToken(userId: String = UUID().uuidString) -> String {
        let userData: [String: Any] = [
            "id": userId,
            "email": "tester-\(userId.prefix(8))@fctest.com",
            "username": "Tester \(userId.prefix(6))",
            "avatar": ""
        ]
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

    private func createCommentSync(urlId: String, text: String, ssoToken: String) {
        let done = expectation(description: "create-\(text.prefix(20))")
        let tenantId = testTenantId!
        let encodedSSO = ssoToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "\(host)/comments/\(tenantId)?broadcastId=\(UUID().uuidString)&urlId=\(urlId)&sso=\(encodedSSO)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "comment": text,
            "commenterName": "Tester",
            "commenterEmail": "tester@fctest.com",
            "url": urlId,
            "urlId": urlId
        ]
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    private func launchApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-test", testTenantId!, urlId, ssoToken]
        app.launch()
        return app
    }

    // MARK: - Tests

    func testCommentsRenderedInOrder() {
        let urlId = "uitest-order-\(Int(Date().timeIntervalSince1970))"
        let sso = makeSecureSSOToken()

        createCommentSync(urlId: urlId, text: "First comment", ssoToken: sso)
        createCommentSync(urlId: urlId, text: "Second comment", ssoToken: sso)
        createCommentSync(urlId: urlId, text: "Third comment", ssoToken: sso)

        let app = launchApp(urlId: urlId, ssoToken: sso)

        // Wait for comments to load
        let thirdComment = app.staticTexts["Third comment"]
        XCTAssertTrue(thirdComment.waitForExistence(timeout: 15), "Third comment should appear")
        XCTAssertTrue(app.staticTexts["Second comment"].exists, "Second comment should exist")
        XCTAssertTrue(app.staticTexts["First comment"].exists, "First comment should exist")

        // With newest-first sort, Third should be above First
        let thirdFrame = app.staticTexts["Third comment"].frame
        let firstFrame = app.staticTexts["First comment"].frame
        XCTAssertLessThan(thirdFrame.minY, firstFrame.minY, "Newest comment (Third) should be above oldest (First)")
    }

    func testPaginationLoadsMore() {
        let urlId = "uitest-paginate-\(Int(Date().timeIntervalSince1970))"
        let sso = makeSecureSSOToken()

        // Seed 35 comments (exceeds default page size of 30)
        for i in 1...35 {
            createCommentSync(urlId: urlId, text: "Comment \(i)", ssoToken: sso)
        }

        let app = launchApp(urlId: urlId, ssoToken: sso)

        // Wait for first page
        XCTAssertTrue(
            app.staticTexts["Comment 35"].waitForExistence(timeout: 15),
            "Newest comment should appear on first page"
        )

        // Scroll to bottom to find pagination
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<5 { scrollView.swipeUp() }

        // Find and tap the Next button
        let nextButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Next pagination button should be visible")

        nextButton.tap()

        // Wait for load
        sleep(3)

        // Scroll down aggressively to find the newly loaded comments
        for _ in 0..<10 { scrollView.swipeUp() }

        // "Comment 1" is the oldest — it should be at the very bottom after loading page 2
        let comment1 = app.staticTexts["Comment 1"]
        let found = comment1.waitForExistence(timeout: 5)

        // Also try scrolling up in case the new comments were inserted above
        if !found {
            for _ in 0..<10 { scrollView.swipeDown() }
        }

        XCTAssertTrue(
            app.staticTexts["Comment 1"].exists,
            "Oldest comment (Comment 1) should be findable after loading more"
        )
    }
}
