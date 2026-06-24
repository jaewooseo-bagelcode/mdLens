import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Builds the mdLens Slack app manifest and opens Slack's "create app from manifest"
/// deep link in the browser (same pattern as AgentB's SlackManifestService).
enum ManifestService {
    /// User-token + Socket Mode app: receives the user's own reaction_added, reads files.
    /// No bot user needed — mdLens renders locally per the authorizing user.
    static func manifestJSON() -> String {
        let manifest: [String: Any] = [
            "display_information": [
                "name": "mdLens",
                "description": "Opens .html / .md from Slack in mdLens when you react 👀",
                "background_color": "#0e7c7b",
            ],
            "oauth_config": [
                "scopes": [
                    "user": [
                        "reactions:read", "files:read",
                        "channels:history", "groups:history", "im:history", "mpim:history",
                    ],
                ],
            ],
            "settings": [
                "event_subscriptions": [
                    "user_events": ["reaction_added"],
                ],
                "interactivity": ["is_enabled": false],
                "org_deploy_enabled": false,
                "socket_mode_enabled": true,
                "token_rotation_enabled": false,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    static func createAppURL() -> URL? {
        let json = manifestJSON()
        guard let encoded = json.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://api.slack.com/apps?new_app=1&manifest_json=\(encoded)")
    }

    @MainActor
    static func openCreateApp() {
        #if canImport(AppKit)
        if let url = createAppURL() { NSWorkspace.shared.open(url) }
        #endif
    }
}
