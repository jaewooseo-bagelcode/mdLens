import Foundation

/// A renderable file referenced by a Slack message (Sendable so it can cross async boundaries).
struct SlackFile: Sendable {
    let name: String
    let downloadURL: String
    let filetype: String

    init?(json f: [String: Any]) {
        guard let url = (f["url_private_download"] as? String) ?? (f["url_private"] as? String) else { return nil }
        self.name = (f["name"] as? String) ?? "document.html"
        self.downloadURL = url
        self.filetype = (f["filetype"] as? String) ?? ""
    }

    var isRenderable: Bool {
        let ext = name.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        let renderable: Set<String> = ["html", "htm", "md", "markdown", "mdown", "mkd"]
        return renderable.contains(ext) || renderable.contains(filetype.lowercased())
    }
}

/// Minimal Slack Web API client (only what the viewer needs). Sendable: just two tokens.
struct SlackAPI: Sendable {
    let webToken: String   // user (xoxp-) or bot (xoxb-) token for Web API calls
    let appToken: String   // app-level (xapp-) token for Socket Mode

    enum APIError: Error { case http(Int), notOK(String), badResponse }

    // MARK: Generic POST (application/x-www-form-urlencoded)

    private func post(_ method: String, token: String, params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        if (json["ok"] as? Bool) != true {
            throw APIError.notOK(json["error"] as? String ?? "unknown")
        }
        return json
    }

    // MARK: Endpoints

    /// Opens a Socket Mode WebSocket URL using the app-level token.
    func openConnection() async throws -> URL {
        let json = try await post("apps.connections.open", token: appToken, params: [:])
        guard let s = json["url"] as? String, let url = URL(string: s) else { throw APIError.badResponse }
        return url
    }

    func authTestUserID() async throws -> String {
        let json = try await post("auth.test", token: webToken, params: [:])
        guard let id = json["user_id"] as? String else { throw APIError.badResponse }
        return id
    }

    /// Fetches the message at (channel, ts) and returns its renderable files.
    /// Tries conversations.history first (top-level messages), then conversations.replies (thread replies).
    func filesForMessage(channel: String, ts: String) async throws -> [SlackFile] {
        if let files = try? await historyFiles(channel: channel, ts: ts), !files.isEmpty {
            return files
        }
        return (try? await replyFiles(channel: channel, ts: ts)) ?? []
    }

    private func parseFiles(_ message: [String: Any]?) -> [SlackFile] {
        let raw = message?["files"] as? [[String: Any]] ?? []
        return raw.compactMap(SlackFile.init(json:))
    }

    private func historyFiles(channel: String, ts: String) async throws -> [SlackFile] {
        let json = try await post("conversations.history", token: webToken, params: [
            "channel": channel, "latest": ts, "oldest": ts, "inclusive": "true", "limit": "1",
        ])
        return parseFiles((json["messages"] as? [[String: Any]])?.first)
    }

    private func replyFiles(channel: String, ts: String) async throws -> [SlackFile] {
        let json = try await post("conversations.replies", token: webToken, params: [
            "channel": channel, "ts": ts, "latest": ts, "oldest": ts, "inclusive": "true", "limit": "1",
        ])
        let messages = json["messages"] as? [[String: Any]] ?? []
        let match = messages.first(where: { ($0["ts"] as? String) == ts }) ?? messages.first
        return parseFiles(match)
    }

    /// Downloads a file's private content to a temp file and returns its local URL.
    func download(file: SlackFile) async throws -> URL {
        guard let url = URL(string: file.downloadURL) else { throw APIError.badResponse }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(webToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mdlens-slack", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("\(UUID().uuidString)-\(file.name)")
        try data.write(to: out)
        return out
    }
}
