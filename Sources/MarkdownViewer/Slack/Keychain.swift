import Foundation
import Security

/// Minimal Keychain wrapper for per-user Slack token storage (generic password
/// items). mdLens creates and reads its own items under its bundle namespace, so
/// a Developer ID-signed build accesses them without an ACL prompt.
enum Keychain {
    /// Namespaced to the running bundle so a dev build (com.sugarscone.mdlens.dev)
    /// and the release (com.sugarscone.mdlens) keep separate tokens, and each app
    /// only ever reads items it created itself → no ACL prompt on a signed build.
    static let service = Bundle.main.bundleIdentifier ?? "com.sugarscone.mdlens"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Replace if present.
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Account keys
    static let appTokenAccount = "app_token"
    static let userTokenAccount = "user_token"
}
