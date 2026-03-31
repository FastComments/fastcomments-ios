import XCTest
import CommonCrypto

/// Base class for UI tests. Handles tenant creation, SSO, app launching, and UI interaction helpers.
class UITestBase: XCTestCase {

    var testTenantId: String!
    var testTenantEmail: String!
    var testTenantApiKey: String!
    var app: XCUIApplication!

    private let host = "https://fastcomments.com"
    private let e2eApiKey = "T0ph B3st"

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        let suffix = UUID().uuidString.prefix(8)
        let email = "ios-uitest-\(suffix)@fctest.com"
        testTenantEmail = email

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpShouldSetCookies = true
        let session = URLSession(configuration: sessionConfig)

        // Sign up tenant
        let signupDone = expectation(description: "signup")
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
        XCTAssertNotNil(testTenantId)

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
        XCTAssertNotNil(testTenantApiKey)
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

    // MARK: - SSO

    func makeSecureSSOToken(userId: String = UUID().uuidString, isAdmin: Bool = false) -> String {
        var userData: [String: Any] = [
            "id": userId,
            "email": "tester-\(userId.prefix(8))@fctest.com",
            "username": "Tester \(userId.prefix(6))",
            "avatar": ""
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

    // MARK: - App Launch

    @discardableResult
    func launchApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-test", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    func makeUrlId(_ testName: String = #function) -> String {
        let sanitized = testName.replacingOccurrences(of: "()", with: "")
        return "uitest-\(sanitized)-\(Int(Date().timeIntervalSince1970))"
    }

    // MARK: - UI Interaction Helpers

    /// Type a comment in the input bar and submit it.
    func typeComment(_ text: String) {
        let input = app.textViews["comment-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Comment input should exist")
        input.tap()
        input.typeText(text)

        let submit = app.buttons["comment-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
    }

    /// Tap the context menu on a comment and select an action.
    func tapMenu(commentId: String, action: String) {
        let menu = app.buttons["menu-\(commentId)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Menu button should exist for \(commentId)")
        menu.tap()

        let actionButton = app.buttons[action]
        XCTAssertTrue(actionButton.waitForExistence(timeout: 5), "Menu action '\(action)' should exist")
        actionButton.tap()
    }

    /// Wait for an accessibility identifier to appear.
    @discardableResult
    func waitForId(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Element '\(identifier)' should appear")
        return element
    }

    /// Seed a comment via API (for cases where UI interaction isn't needed).
    func seedComment(urlId: String, text: String, ssoToken: String) {
        let done = expectation(description: "seed-\(text.prefix(15))")
        let encodedSSO = ssoToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "\(host)/comments/\(testTenantId!)/?broadcastId=\(UUID().uuidString)&urlId=\(urlId)&sso=\(encodedSSO)")!

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

    /// Update a comment via admin API (for pin/lock/etc).
    func adminUpdateComment(commentId: String, params: [String: Any]) {
        let done = expectation(description: "update-\(commentId.prefix(8))")
        let url = URL(string: "\(host)/api/v1/comments/\(commentId)?tenantId=\(testTenantId!)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(testTenantApiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try! JSONSerialization.data(withJSONObject: params)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    /// Fetch the latest comment ID for a urlId via admin API. Retries up to 3 times.
    func fetchLatestCommentId(urlId: String) -> String? {
        for attempt in 1...3 {
            var result: String?
            let done = expectation(description: "fetch-\(attempt)")
            let url = URL(string: "\(host)/api/v1/comments?tenantId=\(testTenantId!)&urlId=\(urlId)&limit=1")!
            var request = URLRequest(url: url)
            request.setValue(testTenantApiKey, forHTTPHeaderField: "x-api-key")
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let comments = json["comments"] as? [[String: Any]],
                   let first = comments.first {
                    result = first["_id"] as? String
                } else if let data = data {
                    let body = String(data: data, encoding: .utf8) ?? "nil"
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("[UITest] fetchLatestCommentId attempt \(attempt): status=\(status) body=\(body.prefix(200))")
                }
                done.fulfill()
            }.resume()
            wait(for: [done], timeout: 10)
            if let result = result { return result }
            if attempt < 3 { sleep(1) }
        }
        return nil
    }
}
