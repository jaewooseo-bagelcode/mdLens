import SwiftUI
import AppKit

/// Owns the opt-in Slack listener lifecycle. Resident only when tokens exist in
/// the Keychain; otherwise mdLens stays a pure viewer with zero background work.
/// `isActive` drives the MenuBarExtra's visibility.
@MainActor
@Observable
final class SlackController {
    /// Single instance owned by the app; started once at launch.
    static let shared = SlackController()
    private init() {}

    /// True once Slack is configured and the listener is running. Drives the menu bar item.
    var isActive = false
    /// Short human-readable state for the menu (e.g. "Listening for 👀").
    var statusText = "Not connected"

    private var client: SocketModeClient?
    private var api: SlackAPI?
    private var triggerEmoji = "eyes"
    private var didStartAtLaunch = false

    /// Start listening if tokens are present. Safe to call at launch — when not
    /// configured it does nothing (no prompt, no background activity). Idempotent
    /// across the app's many document windows.
    func startIfConfigured() {
        guard !didStartAtLaunch else { return }
        didStartAtLaunch = true
        guard let cfg = SlackConfig.resolve() else {
            isActive = false
            statusText = "Not connected"
            return
        }
        start(with: cfg)
    }

    /// Begin a Socket Mode session for the given tokens (also called right after setup).
    func start(with cfg: SlackConfig) {
        stop()
        let api = SlackAPI(webToken: cfg.webToken, appToken: cfg.appToken)
        self.api = api
        triggerEmoji = cfg.triggerEmoji

        let client = SocketModeClient(api: api) { [weak self] reaction in
            Task { @MainActor in self?.handle(reaction) }
        }
        self.client = client
        client.start()

        isActive = true
        statusText = "Listening for :\(triggerEmoji):"

        Task {
            if let id = try? await api.authTestUserID() {
                statusText = "Listening for :\(triggerEmoji): (\(id))"
            } else {
                statusText = "Auth failed — reconnect"
            }
        }
    }

    /// Stop the listener but keep tokens (e.g. on quit). Idempotent.
    func stop() {
        client?.stop()
        client = nil
        api = nil
    }

    /// Stop and forget tokens. mdLens reverts to a pure viewer.
    func disconnect() {
        stop()
        Keychain.delete(Keychain.appTokenAccount)
        Keychain.delete(Keychain.userTokenAccount)
        isActive = false
        statusText = "Not connected"
    }

    // MARK: - Reaction handling

    private func handle(_ r: SocketModeClient.Reaction) {
        guard let api, r.reaction == triggerEmoji else { return }
        Task {
            do {
                let files = try await api.filesForMessage(channel: r.channel, ts: r.ts)
                for file in files where file.isRenderable {
                    let local = try await api.download(file: file)
                    Self.openInNewWindow(local)
                }
            } catch {
                FileHandle.standardError.write(Data("[slack] reaction error: \(error)\n".utf8))
            }
        }
    }

    /// Open a downloaded file in a new mdLens document window by re-launching this
    /// same app with the file — DocumentGroup spawns the window (.html and .md both handled).
    private static func openInNewWindow(_ url: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: cfg)
    }
}
