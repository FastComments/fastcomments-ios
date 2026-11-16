import XCTest
import CommonCrypto
import FastCommentsSwift

/// Base class for UI tests. Handles tenant creation, SSO, app launching, and UI interaction helpers.
class UITestBase: XCTestCase {

    var testTenantId: String!
    var testTenantEmail: String!
    var testTenantApiKey: String!
    var app: XCUIApplication!

    private let host = "https://fastcomments.com"
    private let e2eApiKey = "T0ph B3st"

    /// API config authenticated with the test tenant's API key.
    var adminApiConfig: FastCommentsSwiftAPIConfiguration {
        FastCommentsSwiftAPIConfiguration(customHeaders: ["x-api-key": testTenantApiKey ?? ""])
    }

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
            req.httpBody =
                "username=\(username)&email=\(email)&companyName=\(username)&domains=\(username).example.com&packageId=adv&noTracking=true"
                .data(using: .utf8)
            session.dataTask(with: req) { _, _, _ in done() }.resume()
        }

        // Get tenant ID
        let encodedKey = e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let tenantData = syncFetch(
            url: URL(string: "\(host)/test-e2e/api/tenant/by-email/\(email)?API_KEY=\(encodedKey)")!)
        if let json = try? JSONSerialization.jsonObject(with: tenantData) as? [String: Any],
            let tenant = json["tenant"] as? [String: Any]
        {
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

    func makeSecureSSOToken(
        userId: String = UUID().uuidString, username: String? = nil, isAdmin: Bool = false
    ) -> String {
        var userData: [String: Any] = [
            "id": userId,
            "email": "tester-\(userId.prefix(8))@fctest.com",
            "username": username ?? "Tester \(userId.prefix(6))",
            "avatar": "",
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
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBytes.baseAddress, key.count,
                    msgBytes.baseAddress, messageData.count,
                    &hmac)
            }
        }
        let hash = hmac.map { String(format: "%02x", $0) }.joined()

        let payload: [String: Any] = [
            "userDataJSONBase64": userDataBase64,
            "verificationHash": hash,
            "timestamp": timestamp,
        ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: payloadData, encoding: .utf8)!
    }

    // MARK: - App Launch

    @discardableResult
    func launchApp(urlId: String, ssoToken: String, extraArguments: [String] = []) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-test", testTenantId, urlId, ssoToken] + extraArguments
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchFeedApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-feed-test", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchFeedComposerApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-feed-composer-test", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchFullFeedApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-full-feed-test", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchFeedLifecycleApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-feed-lifecycle-test", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchFollowTestApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-follow-test", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    @discardableResult
    func launchFollowDemoTestApp(urlId: String, ssoToken: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-follow-demo-test", testTenantId, urlId, ssoToken]
        application.launch()
        app = application
        return application
    }

    func makeUrlId(_ testName: String = #function) -> String {
        let sanitized = testName.replacingOccurrences(of: "()", with: "")
        return "uitest-\(sanitized)-\(Int(Date().timeIntervalSince1970))"
    }

    // MARK: - Custom Config

    /// Save a tenant-wide widget config (domain and urlId "*") through the e2e API, which the typed SDK doesn't cover.
    func createCustomConfig(_ widgetConfig: [String: Any], file: StaticString = #file, line: UInt = #line) {
        let encodedKey = e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        var request = URLRequest(url: URL(string: "\(host)/test-e2e/api/custom-configs?API_KEY=\(encodedKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "tenantId": testTenantId!,
            "name": "iOS UI Test Config",
            "domain": "*",
            "urlId": "*",
            "config": widgetConfig,
        ])
        let (_, response) = try! syncFetchRaw(url: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertTrue((200..<300).contains(status), "createCustomConfig failed: \(status)", file: file, line: line)
    }

    /// Comments load with the server's config, so this waits out config caching before the app is launched.
    func waitForPollCreationEnabled(urlId: String, ssoToken: String, file: StaticString = #file, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let sem = DispatchSemaphore(value: 0)
            var pollCreation: PollCreationMode?
            Task {
                defer { sem.signal() }
                let response = try? await PublicAPI.getCommentsPublic(
                    tenantId: self.testTenantId,
                    urlId: urlId,
                    options: PublicAPI.GetCommentsPublicOptions(sso: ssoToken, includeConfig: true)
                )
                pollCreation = response?.customConfig?.pollCreation
            }
            sem.wait()
            if pollCreation == ._2 { return }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("Poll creation never became enabled", file: file, line: line)
    }

    // MARK: - UI Interaction Helpers

    /// Keep a screenshot in the test results, for checking how a screen looks.
    func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Holds the screen still for a moment when the dual-simulator runner is recording a video for review
    /// (`run_dual_sim_tests.py --record`), so each state is visible. Does nothing in a normal run.
    func holdForRecording() {
        guard SyncClient.recordingHold > 0 else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(SyncClient.recordingHold))
    }

    /// Build a poll in the composer, post it with a comment, and return the new comment's id.
    @discardableResult
    func buildAndPostPoll(
        urlId: String, comment: String, question: String, options: [String],
        configure: (() -> Void)? = nil, file: StaticString = #file, line: UInt = #line
    ) -> String {
        let pollButton = app.buttons["poll-toolbar-button"]
        XCTAssertTrue(pollButton.waitForExistence(timeout: 15), "Poll button should show", file: file, line: line)
        pollButton.tap()

        fillPollBuilder(question: question, options: options)
        configure?()
        attachScreenshot("poll-builder")

        typeComment(comment)

        XCTAssertTrue(
            app.staticTexts[question].waitForExistence(timeout: 15), "Posted poll should render", file: file, line: line
        )
        return fetchLatestCommentId(urlId: urlId, file: file, line: line) ?? ""
    }

    func fillPollBuilder(question: String, options: [String]) {
        let questionField = waitForId("poll-builder-question")
        questionField.tap()
        questionField.typeText(question)
        for (index, option) in options.enumerated() {
            let field = waitForId("poll-builder-option-\(index)")
            field.tap()
            field.typeText(option)
        }
    }

    func pollOption(_ commentId: String, _ index: Int) -> XCUIElement {
        app.buttons["poll-option-\(commentId)-\(index)"]
    }

    /// The percent an option reads out. Empty while results are hidden.
    func waitForPollPercent(
        _ commentId: String, option index: Int, equals expected: String, timeout: TimeInterval = 20,
        file: StaticString = #file, line: UInt = #line
    ) {
        let element = pollOption(commentId, index)
        pollUntil(timeout: timeout) { element.exists && (element.value as? String) == expected }
        XCTAssertEqual(element.value as? String, expected, "Option \(index) percent", file: file, line: line)
    }

    func waitForPollTotal(
        _ commentId: String, equals expected: String, timeout: TimeInterval = 20,
        file: StaticString = #file, line: UInt = #line
    ) {
        let element = app.staticTexts["poll-total-\(commentId)"]
        pollUntil(timeout: timeout) { element.exists && element.label == expected }
        XCTAssertEqual(element.label, expected, "Poll total", file: file, line: line)
    }

    /// Close a poll through the admin API, as an integration would.
    func adminClosePoll(commentId: String, file: StaticString = #file, line: UInt = #line) {
        adminPatchPoll(
            commentId: commentId, CommentPollPatch(closesAt: ISO8601DateFormatter().string(from: Date())),
            file: file, line: line)
    }

    func adminPatchPoll(
        commentId: String, _ patch: CommentPollPatch, file: StaticString = #file, line: UInt = #line
    ) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            defer { sem.signal() }
            do {
                let response = try await DefaultAPI.patchPoll(
                    tenantId: self.testTenantId,
                    commentId: commentId,
                    commentPollPatch: patch,
                    apiConfiguration: self.adminApiConfig
                )
                XCTAssertEqual(response.status, .success, file: file, line: line)
            } catch {
                XCTFail("adminPatchPoll failed: \(error)", file: file, line: line)
            }
        }
        sem.wait()
    }

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

        // SwiftUI Menu items appear as buttons on iOS — wait for the popover
        let actionButton = app.buttons[action]
        if !actionButton.waitForExistence(timeout: 5) {
            XCTFail("Menu action '\(action)' not found for comment \(commentId)")
            return
        }
        actionButton.tap()
    }

    /// Poll a condition every 50ms until true or timeout.
    func pollUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            usleep(50_000)  // 50ms
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @discardableResult
    func waitForId(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Element '\(identifier)' should appear")
        return element
    }

    @discardableResult
    func seedComment(urlId: String, text: String, ssoToken: String, parentId: String? = nil) -> String? {
        let commentData = CommentData(
            commenterName: "Tester",
            commenterEmail: "tester@fctest.com",
            comment: text,
            parentId: parentId,
            url: urlId,
            urlId: urlId
        )
        let sem = DispatchSemaphore(value: 0)
        var resultId: String?
        Task {
            defer { sem.signal() }
            do {
                let response = try await PublicAPI.createCommentPublic(
                    tenantId: testTenantId,
                    urlId: urlId,
                    broadcastId: UUID().uuidString,
                    commentData: commentData,
                    options: PublicAPI.CreateCommentPublicOptions(
                        sso: ssoToken
                    )
                )
                resultId = response.comment.id
            } catch {
                XCTFail("seedComment failed: \(error)")
            }
        }
        sem.wait()
        return resultId
    }

    @discardableResult
    func seedFeedPost(urlId: String, text: String, ssoToken: String) -> String? {
        let sem = DispatchSemaphore(value: 0)
        var resultId: String?
        Task {
            defer { sem.signal() }
            do {
                let response = try await PublicAPI.createFeedPostPublic(
                    tenantId: testTenantId,
                    createFeedPostParams: CreateFeedPostParams(contentHTML: text),
                    options: PublicAPI.CreateFeedPostPublicOptions(
                        broadcastId: UUID().uuidString,
                        sso: ssoToken
                    )
                )
                resultId = response.feedPost.id
            } catch {
                XCTFail("seedFeedPost failed: \(error)")
            }
        }
        sem.wait()
        return resultId
    }

    @discardableResult
    func adminUpdateComment(commentId: String, params: UpdatableCommentParams) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var success = false
        Task {
            defer { sem.signal() }
            do {
                let response = try await DefaultAPI.updateComment(
                    tenantId: testTenantId,
                    id: commentId,
                    updatableCommentParams: params,
                    apiConfiguration: adminApiConfig
                )
                success = response.status == .success
            } catch {
                XCTFail("adminUpdateComment failed: \(error)")
            }
        }
        sem.wait()
        return success
    }

    /// Poll the admin API until a comment has at least `expected` children.
    func waitForChildCount(
        parentId: String, urlId: String, expected: Int, timeout: TimeInterval = 10, file: StaticString = #file,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let sem = DispatchSemaphore(value: 0)
            var childCount = 0
            Task {
                defer { sem.signal() }
                let response = try? await DefaultAPI.getComments(
                    tenantId: self.testTenantId,
                    options: DefaultAPI.GetCommentsOptions(
                        limit: expected,
                        urlId: urlId,
                        parentId: parentId
                    ),
                    apiConfiguration: self.adminApiConfig
                )
                childCount = response?.comments.count ?? 0
            }
            sem.wait()
            if childCount >= expected { return }
            if Date() > deadline {
                XCTFail(
                    "waitForChildCount: only \(childCount)/\(expected) children found for \(parentId)", file: file,
                    line: line)
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Fetch the latest comment ID for a urlId via admin API.
    func fetchLatestCommentId(urlId: String, file: StaticString = #file, line: UInt = #line) -> String? {
        let sem = DispatchSemaphore(value: 0)
        var resultId: String?
        Task {
            defer { sem.signal() }
            do {
                let response = try await DefaultAPI.getComments(
                    tenantId: testTenantId,
                    options: DefaultAPI.GetCommentsOptions(
                        limit: 1,
                        urlId: urlId
                    ),
                    apiConfiguration: adminApiConfig
                )
                resultId = response.comments.first?.id
            } catch {
                XCTFail("fetchLatestCommentId failed: \(error)", file: file, line: line)
            }
        }
        sem.wait()
        if resultId == nil {
            XCTFail("fetchLatestCommentId: no comments found for urlId=\(urlId)", file: file, line: line)
        }
        return resultId
    }
}
