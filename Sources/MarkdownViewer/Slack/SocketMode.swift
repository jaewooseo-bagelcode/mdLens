import Foundation

/// Slack Socket Mode client: outbound WebSocket, no public endpoint needed.
/// Receives Events API envelopes, acks them, and dispatches reaction_added.
@MainActor
final class SocketModeClient {
    struct Reaction: Sendable { let reaction: String; let user: String; let channel: String; let ts: String }

    private let api: SlackAPI
    private let onReaction: @Sendable (Reaction) -> Void
    private var running = false
    private var connectTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?

    init(api: SlackAPI, onReaction: @escaping @Sendable (Reaction) -> Void) {
        self.api = api
        self.onReaction = onReaction
    }

    func start() {
        running = true
        connectTask = Task { await connectLoop() }
    }

    /// Stop and tear down: cancel the in-flight `receive()` so no further message
    /// is processed after the listener is reported stopped (prevents duplicate
    /// downloads on disconnect/reconnect).
    func stop() {
        running = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectTask?.cancel()
        connectTask = nil
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(Data("[socket] \(s)\n".utf8))
    }

    private func connectLoop() async {
        while running {
            do {
                let url = try await api.openConnection()
                log("connected")
                try await runConnection(url: url)
            } catch {
                log("error: \(error) — retry in 3s")
            }
            if running { try? await Task.sleep(nanoseconds: 3_000_000_000) }
        }
    }

    private func runConnection(url: URL) async throws {
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
            if webSocketTask === task { webSocketTask = nil }
        }

        while running && !Task.isCancelled {
            let message = try await task.receive() // throws on close/cancel → reconnect
            // A message may have arrived before stop() cancelled us; drop it so no
            // reaction is dispatched after the listener is reported stopped.
            guard running && !Task.isCancelled else { return }
            let text: String
            switch message {
            case .string(let s): text = s
            case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
            @unknown default: continue
            }
            if try handle(text: text, task: task) == .disconnect { return } // reconnect
        }
    }

    private enum Outcome { case ok, disconnect }

    private func handle(text: String, task: URLSessionWebSocketTask) throws -> Outcome {
        guard let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ok
        }
        let type = json["type"] as? String

        // Acknowledge any enveloped message immediately (required within 3s).
        if let envelopeID = json["envelope_id"] as? String,
           let ack = try? JSONSerialization.data(withJSONObject: ["envelope_id": envelopeID]),
           let ackStr = String(data: ack, encoding: .utf8) {
            task.send(.string(ackStr)) { _ in }
        }

        if type == "disconnect" { return .disconnect }

        if type == "events_api",
           let payload = json["payload"] as? [String: Any],
           let event = payload["event"] as? [String: Any],
           event["type"] as? String == "reaction_added",
           let reaction = event["reaction"] as? String,
           let user = event["user"] as? String,
           let item = event["item"] as? [String: Any],
           let channel = item["channel"] as? String,
           let ts = item["ts"] as? String {
            onReaction(Reaction(reaction: reaction, user: user, channel: channel, ts: ts))
        }
        return .ok
    }
}
