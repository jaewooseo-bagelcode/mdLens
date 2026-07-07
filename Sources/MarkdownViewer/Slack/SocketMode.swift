import Foundation
import AppKit

/// Slack Socket Mode client: outbound WebSocket, no public endpoint needed.
/// Receives Events API envelopes, acks them, and dispatches reaction_added.
///
/// Liveness: `URLSessionWebSocketTask.receive()` never times out on its own, so a
/// half-open socket (common after sleep/resume) would leave `receive()` blocked
/// forever with no reconnect. Two mechanisms force a reconnect:
///   1. Heartbeat ping every 25s + a 10s pong watchdog → cancels the task (→ receive()
///      throws) when the peer is silently gone.
///   2. `NSWorkspace.didWakeNotification` → cancel the socket immediately on wake.
@MainActor
final class SocketModeClient {
    struct Reaction: Sendable { let reaction: String; let user: String; let channel: String; let ts: String }

    private let api: SlackAPI
    private let onReaction: @Sendable (Reaction) -> Void
    /// Called on each (re)connect so the owner can re-resolve per-session state
    /// (e.g. our own user id) — a transient failure must not stick until relaunch.
    private let onConnect: @Sendable () -> Void
    private var running = false
    private var connectTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var wakeObserver: NSObjectProtocol?

    init(api: SlackAPI,
         onReaction: @escaping @Sendable (Reaction) -> Void,
         onConnect: @escaping @Sendable () -> Void = {}) {
        self.api = api
        self.onReaction = onReaction
        self.onConnect = onConnect
    }

    func start() {
        running = true
        // Force an immediate reconnect on wake — the pre-sleep socket is usually
        // dead, and waiting for the next heartbeat would delay recovery ~35s.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
        connectTask = Task { await connectLoop() }
    }

    /// Stop and tear down: cancel the in-flight `receive()` so no further message
    /// is processed after the listener is reported stopped (prevents duplicate
    /// downloads on disconnect/reconnect).
    func stop() {
        running = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectTask?.cancel()
        connectTask = nil
    }

    private func handleWake() {
        guard running else { return }
        log("system wake — reconnecting")
        webSocketTask?.cancel(with: .goingAway, reason: nil) // receive() throws → connectLoop reconnects
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
        onConnect() // re-resolve per-session state on every (re)connect
        let heartbeat = startHeartbeat(for: task)
        defer {
            heartbeat.cancel()
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

    /// Probe socket liveness: every 25s send a ping and arm a 10s watchdog. If the
    /// pong doesn't arrive (half-open socket) the watchdog cancels the task, forcing
    /// `receive()` to throw so `connectLoop` reconnects. `task.cancel()` is local so
    /// it breaks a hung `receive()` even when the ping callback itself never fires.
    private func startHeartbeat(for task: URLSessionWebSocketTask) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled, let self, self.running else { return }
                let watchdog = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled, let self, self.webSocketTask === task else { return }
                    self.log("pong timeout — forcing reconnect")
                    task.cancel(with: .goingAway, reason: nil)
                }
                task.sendPing { [weak self] error in
                    Task { @MainActor in
                        watchdog.cancel()
                        guard let self, let error, self.webSocketTask === task else { return }
                        self.log("ping failed (\(error)) — forcing reconnect")
                        task.cancel(with: .goingAway, reason: nil)
                    }
                }
            }
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
