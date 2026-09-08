import Foundation
import Security

/// Thin wrapper over Keychain Services for the app's secrets (API keys).
///
/// Secrets used to live in `UserDefaults`, i.e. plaintext in
/// `~/Library/Preferences/com.lyra.Lyra.plist`, readable by any unprivileged
/// process via `defaults read`. They now live in the login keychain as
/// `kSecClassGenericPassword` items; `UserDefaults` keeps nothing but a
/// migration marker.
enum KeychainStore {
    /// Shared keychain service identifier for all Lyra secrets.
    private static let service = "com.lyra.Lyra"

    /// In-memory mirror so hot paths (every transcription request) don't hit
    /// the keychain daemon. Writes go through `set`, which keeps it in sync.
    private static var cache: [String: String] = [:]
    private static let cacheLock = NSLock()

    static func get(_ account: String) -> String? {
        cacheLock.lock()
        if let cached = cache[account] {
            cacheLock.unlock()
            return cached.isEmpty ? nil : cached
        }
        cacheLock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        cacheLock.lock()
        cache[account] = value
        cacheLock.unlock()
        return value.isEmpty ? nil : value
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        cacheLock.lock()
        cache[account] = value
        cacheLock.unlock()

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        guard !value.isEmpty else {
            SecItemDelete(base as CFDictionary)
            return true
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        var addQuery = base
        addQuery[kSecValueData as String] = data
        // Secrets are only needed while the user is logged in and must never
        // sync to iCloud or leave this device.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            fputs("[Keychain] Failed to store '\(account)': OSStatus \(addStatus)\n", stderr)
            return false
        }
        return true
    }

    static func delete(_ account: String) {
        cacheLock.lock()
        cache.removeValue(forKey: account)
        cacheLock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
