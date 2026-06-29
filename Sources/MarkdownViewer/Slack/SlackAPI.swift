import Foundation

/// A renderable file referenced by a Slack message (Sendable so it can cross async boundaries).
struct SlackFile: Sendable {
    let name: String
    let downloadURL: String
    let filetype: String
    let size: Int   // bytes as reported by Slack; 0 when unknown

    init?(json f: [String: Any]) {
        guard let url = (f["url_private_download"] as? String) ?? (f["url_private"] as? String) else { return nil }
        self.name = (f["name"] as? String) ?? "document.html"
        self.downloadURL = url
        self.filetype = (f["filetype"] as? String) ?? ""
        self.size = (f["size"] as? Int) ?? 0
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

    enum APIError: Error { case http(Int), notOK(String), badResponse, tooLarge(Int) }

    /// Hard cap for an ingested document — these are markdown/HTML, not media.
    static let maxDownloadBytes = 25_000_000 // 25MB

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

    /// Returns the files attached to EXACTLY the message at (channel, ts) — never
    /// any other message in the same thread.
    ///
    /// Targeting one message is subtle. The previous version used a zero-width
    /// `oldest==latest` window plus a `?? messages.first` fallback, which could
    /// surface a *different* thread message's files: reacting on a thread root whose
    /// own attachment isn't renderable would open a reply's file. We now fetch with
    /// the canonical single-message idiom (`latest=ts&limit=1&inclusive`) and, for
    /// thread replies, match the exact `ts` with **no fallback**.
    func filesForMessage(channel: String, ts: String) async throws -> [SlackFile] {
        // Top-level (or standalone) message: the newest message at-or-before `ts`
        // is the message itself — but only trust it if the ts matches exactly.
        if let msg = try? await latestMessage(channel: channel, ts: ts),
           (msg["ts"] as? String) == ts {
            return parseFiles(msg)
        }
        // Otherwise it's a thread reply: pull the thread, pick the exact message.
        if let msg = try? await threadMessage(channel: channel, ts: ts) {
            return parseFiles(msg)
        }
        return []
    }

    private func parseFiles(_ message: [String: Any]?) -> [SlackFile] {
        let raw = message?["files"] as? [[String: Any]] ?? []
        return raw.compactMap(SlackFile.init(json:))
    }

    /// The single most recent message at or before `ts` (canonical fetch-one idiom).
    private func latestMessage(channel: String, ts: String) async throws -> [String: Any]? {
        let json = try await post("conversations.history", token: webToken, params: [
            "channel": channel, "latest": ts, "inclusive": "true", "limit": "1",
        ])
        return (json["messages"] as? [[String: Any]])?.first
    }

    /// The exact message `ts` within its thread, or nil — never a sibling/fallback.
    private func threadMessage(channel: String, ts: String) async throws -> [String: Any]? {
        let json = try await post("conversations.replies", token: webToken, params: [
            "channel": channel, "ts": ts, "limit": "200",
        ])
        let messages = json["messages"] as? [[String: Any]] ?? []
        return messages.first(where: { ($0["ts"] as? String) == ts })
    }

    /// Streams a file's private content to a temp file (no full in-memory buffer)
    /// and returns its local URL, rejecting anything over `maxDownloadBytes`.
    func download(file: SlackFile) async throws -> URL {
        if file.size > Self.maxDownloadBytes { throw APIError.tooLarge(file.size) }
        guard let url = URL(string: file.downloadURL) else { throw APIError.badResponse }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(webToken)", forHTTPHeaderField: "Authorization")
        let (tempURL, resp) = try await URLSession.shared.download(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        // Slack may omit size in the message event — enforce it post-download too.
        let downloaded = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
        if downloaded > Self.maxDownloadBytes {
            try? FileManager.default.removeItem(at: tempURL)
            throw APIError.tooLarge(downloaded)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mdlens-slack", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Reduce to a single path component so a crafted Slack filename can't add
        // subdirs / traverse out of the temp dir.
        let safeName = (file.name as NSString).lastPathComponent
        let out = dir.appendingPathComponent("\(UUID().uuidString)-\(safeName.isEmpty ? "document" : safeName)")
        do {
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.moveItem(at: tempURL, to: out)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        return out
    }
}
