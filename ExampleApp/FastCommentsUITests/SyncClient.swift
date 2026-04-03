import Foundation

/// Client for the dual-sim sync server at localhost:9999.
/// Tests use this to coordinate actions between two simulator processes.
enum SyncClient {

    /// Set by each test class based on its role (UserA or UserB).
    static var currentRole: String = "unknown"

    static var baseURL: String {
        if let config = readConfigFile(role: currentRole) {
            return config["FC_SYNC_URL"] ?? "http://localhost:9999"
        }
        return "http://localhost:9999"
    }

    static var role: String { currentRole }

    private static func readConfigFile(role: String) -> [String: String]? {
        let path = "/tmp/fc-uitest-\(role).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return json
    }

    /// Signal that this role is ready for a specific round.
    static func signalReady(round: String) {
        let url = URL(string: "\(baseURL)/ready?role=\(role)&round=\(round)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        syncRequest(request)
    }

    /// Block until the specified role signals ready for a round.
    static func waitFor(role waitRole: String, round: String, timeout: Int = 60) {
        let url = URL(string: "\(baseURL)/wait?waitFor=\(waitRole)&round=\(round)&timeout=\(timeout)")!
        syncRequest(URLRequest(url: url))
    }

    /// Store data for a round.
    static func postData(round: String, data: [String: Any]) {
        let url = URL(string: "\(baseURL)/data?round=\(round)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: data)
        syncRequest(request)
    }

    /// Retrieve data for a round.
    static func getData(round: String) -> [String: Any] {
        let url = URL(string: "\(baseURL)/data?round=\(round)")!
        let data = syncFetch(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    // MARK: - Private

    private static func syncRequest(_ request: URLRequest) {
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
        sem.wait()
    }

    private static func syncFetch(_ url: URL) -> Data {
        let sem = DispatchSemaphore(value: 0)
        var result = Data()
        URLSession.shared.dataTask(with: url) { data, _, _ in
            result = data ?? Data()
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }
}
