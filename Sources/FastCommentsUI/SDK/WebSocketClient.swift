import Foundation
import FastCommentsSwift

/// Native WebSocket client using URLSessionWebSocketTask.
/// Handles connection, reconnection with exponential backoff, and heartbeat.
final class WebSocketClient: @unchecked Sendable {
    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
    }

    var onEvent: ((LiveEvent) -> Void)?
    var onConnectionStatusChange: ((Bool, Date?) -> Void)?
    private(set) var state: ConnectionState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var pingTimer: Timer?
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 10
    private var tenantIdWS: String?
    private var urlIdWS: String?
    private var userIdWS: String?
    private var lastEventTime: Date?

    init() {
        self.session = URLSession(configuration: .default)
    }

    func connect(tenantIdWS: String, urlIdWS: String, userIdWS: String?, basePath: String = "https://fastcomments.com") {
        disconnect()

        self.tenantIdWS = tenantIdWS
        self.urlIdWS = urlIdWS
        self.userIdWS = userIdWS
        self.state = .connecting

        // Build WebSocket URL
        var components = URLComponents()
        let isEU = basePath.contains("eu.fastcomments")
        components.scheme = "wss"
        components.host = isEU ? "ws-eu.fastcomments.com" : "ws.fastcomments.com"
        components.path = "/sub"
        components.queryItems = [
            URLQueryItem(name: "tenantId", value: tenantIdWS),
            URLQueryItem(name: "urlId", value: urlIdWS),
        ]
        if let userIdWS = userIdWS {
            components.queryItems?.append(URLQueryItem(name: "userId", value: userIdWS))
        }

        guard let url = components.url else {
            state = .disconnected
            return
        }

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        state = .connected
        reconnectAttempts = 0

        onConnectionStatusChange?(true, lastEventTime)
        startPing()
        receiveMessage()
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
    }

    // MARK: - Private

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self.receiveMessage()

            case .failure:
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        lastEventTime = Date()

        guard let data = text.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let event = try decoder.decode(LiveEvent.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        } catch {
            // Try decoding as an array of events (some WS implementations batch)
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let events = try decoder.decode([LiveEvent].self, from: data)
                DispatchQueue.main.async { [weak self] in
                    for event in events {
                        self?.onEvent?(event)
                    }
                }
            } catch {
                // Silently ignore unparseable messages (heartbeat acks, etc.)
            }
        }
    }

    private func handleDisconnect() {
        state = .disconnected
        pingTimer?.invalidate()
        pingTimer = nil

        DispatchQueue.main.async { [weak self] in
            self?.onConnectionStatusChange?(false, self?.lastEventTime)
        }

        attemptReconnect()
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts,
              let tenantIdWS = tenantIdWS,
              let urlIdWS = urlIdWS else { return }

        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 30.0) // exponential backoff, max 30s

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.state == .disconnected else { return }
            self.connect(tenantIdWS: tenantIdWS, urlIdWS: urlIdWS, userIdWS: self.userIdWS)
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if error != nil {
                    self?.handleDisconnect()
                }
            }
        }
    }
}
