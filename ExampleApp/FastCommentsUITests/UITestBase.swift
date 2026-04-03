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

    /// Subclasses must override to provide a stable tenant email (e.g. "ios-comment-crud-ui@fctest.com").
    var stableTenantEmail: String {
        preconditionFailure("Subclasses must override stableTenantEmail")
    }

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        let email = stableTenantEmail
        let username = String(email.split(separator: "@").first ?? "")
        testTenantEmail = email

        // Delete any leftover tenant from a previous failed run
        deleteTenantByEmailSync(email)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpShouldSetCookies = true
        let session = URLSession(configuration: sessionConfig)

        // Sign up tenant
        syncRequest(session: session) { done in
            let signupURL = URL(string: "\(self.host)/auth/tenant-signup")!
            var req = URLRequest(url: signupURL)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = "username=\(username)&email=\(email)&companyName=\(username)&domains=\(username).example.com&packageId=adv&noTracking=true".data(using: .utf8)
            session.dataTask(with: req) { _, _, _ in done() }.resume()
        }

        // Get tenant ID
        let encodedKey = e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let tenantData = syncFetch(url: URL(string: "\(host)/test-e2e/api/tenant/by-email/\(email)?API_KEY=\(encodedKey)")!)
        if let json = try? JSONSerialization.jsonObject(with: tenantData) as? [String: Any],
           let tenant = json["tenant"] as? [String: Any] {
            testTenantId = tenant["_id"] as? String
        }
        XCTAssertNotNil(testTenantId, "Should have tenant ID")

        // Get API key
        let apiSecretData = syncFetch(session: session, url: URL(string: "\(host)/auth/my-account/api-secret")!)
        let html = String(data: apiSecretData, encoding: .utf8) ?? ""
        if let range = html.range(of: #"value="([A-Z0-9]+)""#, options: .regularExpression) {
            let match = String(html[range])
            testTenantApiKey = String(match.dropFirst(7).dropLast(1))
        }
        XCTAssertNotNil(testTenantApiKey, "Should have API key")
    }

    override func tearDownWithError() throws {
        if let email = testTenantEmail {
            let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            let encodedKey = e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let url = URL(string: "\(host)/test-e2e/api/tenant/by-email/\(encodedEmail)?API_KEY=\(encodedKey)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try? syncFetchRaw(url: request)
        }
    }

    // MARK: - Synchronous HTTP helpers

    private func syncFetch(session: URLSession = .shared, url: URL) -> Data {
        let sem = DispatchSemaphore(value: 0)
        var resultData = Data()
        session.dataTask(with: url) { data, _, _ in
            resultData = data ?? Data()
            sem.signal()
        }.resume()
        sem.wait()
        return resultData
    }

    private func syncFetchRaw(url: URLRequest) throws -> (Data, URLResponse?) {
        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: URLResponse?
        URLSession.shared.dataTask(with: url) { data, response, _ in
            resultData = data
            resultResponse = response
            sem.signal()
        }.resume()
        sem.wait()
        return (resultData ?? Data(), resultResponse)
    }

    private func syncRequest(session: URLSession = .shared, _ block: (@escaping () -> Void) -> Void) {
        let sem = DispatchSemaphore(value: 0)
        block { sem.signal() }
        sem.wait()
    }

    private func deleteTenantByEmailSync(_ email: String) {
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let encodedKey = e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "\(host)/test-e2e/api/tenant/by-email/\(encodedEmail)?API_KEY=\(encodedKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? syncFetchRaw(url: request)
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

    func typeComment(_ text: String) {
        let input = app.textViews["comment-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Comment input should exist")
        input.tap()
        input.typeText(text)

        let submit = app.buttons["comment-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
    }

    func tapMenu(commentId: String, action: String) {
        let menu = app.buttons["menu-\(commentId)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Menu button should exist for \(commentId)")
        menu.tap()

        let actionButton = app.buttons[action]
        XCTAssertTrue(actionButton.waitForExistence(timeout: 5), "Menu action '\(action)' should exist")
        actionButton.tap()
    }

    /// Poll a condition every 50ms until true or timeout.
    func pollUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            usleep(50_000) // 50ms
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @discardableResult
    func waitForId(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Element '\(identifier)' should appear")
        return element
    }

    func seedComment(urlId: String, text: String, ssoToken: String, parentId: String? = nil) {
        let encodedSSO = ssoToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "\(host)/comments/\(testTenantId!)/?broadcastId=\(UUID().uuidString)&urlId=\(urlId)&sso=\(encodedSSO)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "comment": text,
            "commenterName": "Tester",
            "commenterEmail": "tester@fctest.com",
            "url": urlId,
            "urlId": urlId
        ]
        if let parentId = parentId {
            body["parentId"] = parentId
        }
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)
        _ = try? syncFetchRaw(url: request)
    }

    @discardableResult
    func adminUpdateComment(commentId: String, params: [String: Any]) -> Bool {
        let url = URL(string: "\(host)/api/v1/comments/\(commentId)?tenantId=\(testTenantId!)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(testTenantApiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try! JSONSerialization.data(withJSONObject: params)
        let (data, response) = (try? syncFetchRaw(url: request)) ?? (Data(), nil)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            XCTFail("adminUpdateComment failed: status=\(status) body=\(body.prefix(200))")
            return false
        }
        return true
    }

    /// Fetch the latest comment ID for a urlId via admin API. Retries up to 3 times.
    func fetchLatestCommentId(urlId: String, file: StaticString = #file, line: UInt = #line) -> String? {
        for attempt in 1...3 {
            let urlString = "\(host)/api/v1/comments?tenantId=\(testTenantId!)&urlId=\(urlId)&limit=1"
            guard let url = URL(string: urlString) else {
                XCTFail("Bad URL: \(urlString)", file: file, line: line)
                return nil
            }
            var request = URLRequest(url: url)
            request.setValue(testTenantApiKey, forHTTPHeaderField: "x-api-key")

            let sem = DispatchSemaphore(value: 0)
            var resultId: String?
            var debugInfo = "no response"

            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { sem.signal() }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
                debugInfo = "status=\(status) body=\(String(body.prefix(300)))"

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let comments = json["comments"] as? [[String: Any]],
                      let first = comments.first,
                      let id = (first["_id"] ?? first["id"]) as? String else { return }
                resultId = id
            }.resume()

            sem.wait()

            if let id = resultId { return id }
            if attempt == 3 {
                XCTFail("fetchLatestCommentId failed: \(debugInfo)", file: file, line: line)
            } else {
                usleep(500_000) // 500ms before retry
            }
        }
        return nil
    }
}
