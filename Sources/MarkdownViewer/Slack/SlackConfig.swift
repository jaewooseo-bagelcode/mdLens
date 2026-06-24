import Foundation

/// Runtime Slack tokens, resolved from the Keychain only (populated by the
/// in-app "Connect Slack" setup). No tokens → mdLens stays a pure viewer.
struct SlackConfig {
    let appToken: String   // app-level (xapp-) token for Socket Mode
    let webToken: String   // user (xoxp-) token for Web API calls
    let triggerEmoji: String

    /// Returns nil when either token is missing — the signal that Slack is not configured.
    static func resolve() -> SlackConfig? {
        guard let app = Keychain.get(Keychain.appTokenAccount),
              let user = Keychain.get(Keychain.userTokenAccount),
              !app.isEmpty, !user.isEmpty else { return nil }
        return SlackConfig(appToken: app, webToken: user, triggerEmoji: "eyes")
    }

    /// True when both tokens are present in the Keychain.
    static var isConfigured: Bool { resolve() != nil }
}
