import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

/// Base class for integration tests that hit the real FastComments API.
///
/// Each test creates a tenant via signup with an @fctest.com email (no rate limits),
/// retrieves its API key for secure SSO (admin users), and cleans up in tearDown.
@MainActor
class IntegrationTestBase: XCTestCase {

    private var urlIdsToCleanup: [String] = []
    private var testTenantId: String?
    private var testTenantEmail: String?
    private var testTenantApiKey: String?

    /// Subclasses must override to provide a stable tenant email (e.g. "ios-comment-crud@fctest.com").
    var stableTenantEmail: String {
        preconditionFailure("Subclasses must override stableTenantEmail")
    }

    /// Authenticated API config using the test tenant's own API key.
    var adminApiConfig: FastCommentsSwiftAPIConfiguration {
        FastCommentsSwiftAPIConfiguration(
            customHeaders: ["x-api-key": testTenantApiKey ?? TestConfig.apiKey]
        )
    }

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()

        let email = stableTenantEmail
        let username = String(email.split(separator: "@").first ?? "")
        testTenantEmail = email

        // Delete any leftover tenant from a previous failed run
        await deleteTenantByEmail(email)

        // 1. Sign up tenant via form POST (captures session cookie)
        let signupURL = URL(string: "\(TestConfig.host)/auth/tenant-signup")!
        var signupRequest = URLRequest(url: signupURL)
        signupRequest.httpMethod = "POST"
        signupRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let formBody = "username=\(username)&email=\(email)&companyName=\(username)&domains=\(username).example.com&packageId=adv&noTracking=true"
        signupRequest.httpBody = formBody.data(using: .utf8)

        // Use a shared URLSession that stores cookies
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpShouldSetCookies = true
        let session = URLSession(configuration: sessionConfig)

        let (_, signupResponse) = try await session.data(for: signupRequest)
        guard let httpSignup = signupResponse as? HTTPURLResponse,
              (200..<400).contains(httpSignup.statusCode) else {
            XCTFail("Tenant signup failed")
            return
        }

        // 2. Get tenant ID via e2e test API
        let encodedKey = TestConfig.e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let tenantURL = URL(string: "\(TestConfig.host)/test-e2e/api/tenant/by-email/\(email)?API_KEY=\(encodedKey)")!
        let (tenantData, _) = try await URLSession.shared.data(from: tenantURL)
        let tenantJSON = try JSONSerialization.jsonObject(with: tenantData) as? [String: Any]
        let tenant = tenantJSON?["tenant"] as? [String: Any]
        testTenantId = tenant?["_id"] as? String

        guard testTenantId != nil else {
            XCTFail("Could not get tenant ID for \(email)")
            return
        }

        // 3. Get API key by fetching the API secret page with the signup session
        let apiSecretURL = URL(string: "\(TestConfig.host)/auth/my-account/api-secret")!
        let (apiSecretData, _) = try await session.data(from: apiSecretURL)
        let html = String(data: apiSecretData, encoding: .utf8) ?? ""

        // Extract API key from: value="<KEY>"
        if let range = html.range(of: #"value="([A-Z0-9]+)""#, options: .regularExpression) {
            let match = String(html[range])
            testTenantApiKey = String(match.dropFirst(7).dropLast(1)) // strip value=" and "
        }

        guard testTenantApiKey != nil else {
            XCTFail("Could not extract API key from api-secret page")
            return
        }
    }

    override func tearDown() async throws {
        for urlId in urlIdsToCleanup {
            await cleanupComments(urlId: urlId)
        }
        urlIdsToCleanup.removeAll()

        // Delete the tenant via e2e test API
        if let email = testTenantEmail {
            let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            let encodedKey = TestConfig.e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let url = URL(string: "\(TestConfig.host)/test-e2e/api/tenant/by-email/\(encodedEmail)?API_KEY=\(encodedKey)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: request)
        }

        testTenantId = nil
        testTenantEmail = nil
        testTenantApiKey = nil

        try await super.tearDown()
    }

    // MARK: - SDK Factories

    var tenantId: String { testTenantId! }

    /// Create a secure SSO token for a regular test user.
    private func makeSSOToken(userId: String = UUID().uuidString) -> String {
        let userData = SecureSSOUserData(
            id: userId,
            email: "tester-\(userId.prefix(8))@fctest.com",
            username: "Tester \(userId.prefix(6))",
            avatar: ""
        )
        let sso = try! FastCommentsSSO.createSecure(apiKey: testTenantApiKey!, secureSSOUserData: userData)
        return try! sso.prepareToSend()!
    }

    /// Create a secure SSO token for an admin test user (can pin, lock, block).
    private func makeAdminSSOToken(userId: String = UUID().uuidString) -> String {
        var userData = SecureSSOUserData(
            id: userId,
            email: "admin-\(userId.prefix(8))@fctest.com",
            username: "Admin \(userId.prefix(6))",
            avatar: ""
        )
        userData.isAdmin = true
        let sso = try! FastCommentsSSO.createSecure(apiKey: testTenantApiKey!, secureSSOUserData: userData)
        return try! sso.prepareToSend()!
    }

    /// Create a FastCommentsSDK with a unique urlId and SSO user.
    func makeSDK(testName: String = #function) -> FastCommentsSDK {
        let urlId = makeUrlId(testName: testName)
        let config = FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: makeSSOToken())
        return FastCommentsSDK(config: config)
    }

    /// Create a FastCommentsSDK sharing a specific urlId (distinct SSO user per call).
    func makeSDK(urlId: String) -> FastCommentsSDK {
        let config = FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: makeSSOToken())
        return FastCommentsSDK(config: config)
    }

    /// Create a FastCommentsSDK with admin SSO (for pin, lock, block operations).
    func makeAdminSDK(testName: String = #function) -> FastCommentsSDK {
        let urlId = makeUrlId(testName: testName)
        let config = FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: makeAdminSSOToken())
        return FastCommentsSDK(config: config)
    }

    /// Create an admin SDK sharing a specific urlId.
    func makeAdminSDK(urlId: String) -> FastCommentsSDK {
        let config = FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: makeAdminSSOToken())
        return FastCommentsSDK(config: config)
    }

    /// Create a FastCommentsSDK with a specific SSO user identity (for reconnect / multi-user tests).
    func makeSDK(urlId: String, userId: String) -> FastCommentsSDK {
        let config = FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: makeSSOToken(userId: userId))
        return FastCommentsSDK(config: config)
    }

    /// Create a FastCommentsFeedSDK with a unique urlId and SSO user.
    func makeFeedSDK(testName: String = #function) -> FastCommentsFeedSDK {
        let urlId = makeUrlId(testName: testName)
        let config = FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: makeSSOToken())
        return FastCommentsFeedSDK(config: config)
    }

    /// Create a FastCommentsFeedSDK sharing a specific urlId (distinct SSO user per call).
    func makeFeedSDK(urlId: String) -> FastCommentsFeedSDK {
        let config = FastCommentsWidgetConfig(tenantId: tenantId, urlId: urlId, sso: makeSSOToken())
        return FastCommentsFeedSDK(config: config)
    }

    /// Generate a unique urlId and register it for cleanup.
    func makeUrlId(testName: String = #function) -> String {
        let sanitized = testName
            .replacingOccurrences(of: "()", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let timestamp = Int(Date().timeIntervalSince1970)
        let urlId = "ios-test-\(sanitized)-\(timestamp)"
        urlIdsToCleanup.append(urlId)
        return urlId
    }

    // MARK: - Cleanup

    private func deleteTenantByEmail(_ email: String) async {
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let encodedKey = TestConfig.e2eApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "\(TestConfig.host)/test-e2e/api/tenant/by-email/\(encodedEmail)?API_KEY=\(encodedKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }

    func cleanupComments(urlId: String) async {
        guard let tid = testTenantId else { return }
        do {
            let response = try await DefaultAPI.getComments(
                tenantId: tid, urlId: urlId, apiConfiguration: adminApiConfig
            )
            for comment in (response.comments ?? []) {
                _ = try? await DefaultAPI.deleteComment(
                    tenantId: tid, id: comment.id, apiConfiguration: adminApiConfig
                )
            }
        } catch {}
    }

    // MARK: - Polling

    func waitFor(
        timeout: TimeInterval = 5.0,
        interval: TimeInterval = 0.2,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}
