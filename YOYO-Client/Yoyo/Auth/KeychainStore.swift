import Foundation
import Security

/// A tiny abstraction over `kSecClassGenericPassword` so tests can stub it out
/// without touching the real keychain. The protocol intentionally exposes
/// only string-typed get/set/delete — JWT is the only secret we currently
/// store, so we don't need a richer data type here.
protocol KeychainStoring {
    func readString(forKey key: String) -> String?
    func writeString(_ value: String, forKey key: String)
    func delete(forKey key: String)
    func migrateFromLegacyDefaults(key: String, defaults: UserDefaults)
}

/// Concrete keychain wrapper using `kSecClassGenericPassword`.
///
/// - Service is fixed to the bundle identifier so multiple Yoyo apps (or
///   other products built from this repo) cannot collide.
/// - Accessibility is `kSecAttrAccessibleAfterFirstUnlock` so the token is
///   available to background refresh / extension code paths after the user
///   unlocks the device at least once, but does not leak into backups as
///   plain plaintext-on-screen.
/// - All operations are best-effort and log via `debugLog` on failure; the
///   app must remain usable even if the keychain is unavailable (e.g.
///   simulator without a passcode set).
final class KeychainStore: KeychainStoring {
    static let shared = KeychainStore()

    /// Override point for tests / previews.
    static var instance: KeychainStoring = KeychainStore.shared

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.anyan.YoyoCamera") {
        self.service = service
    }

    func readString(forKey key: String) -> String? {
        read(forKey: key) as? String
    }

    func writeString(_ value: String, forKey key: String) {
        write(value: value, forKey: key)
    }

    func delete(forKey key: String) {
        deleteKeychainItem(forKey: key)
    }

    /// One-shot migration: if the keychain has nothing for `key` but
    /// `defaults` still has a legacy value, copy it across and clear the
    /// legacy entry so we never store the same secret in two places again.
    /// Returns `true` if the migration actually ran.
    @discardableResult
    func migrateFromLegacyDefaults(key: String, defaults: UserDefaults) -> Bool {
        guard readString(forKey: key) == nil,
              let legacy = defaults.string(forKey: key),
              !legacy.isEmpty
        else {
            return false
        }
        writeString(legacy, forKey: key)
        defaults.removeObject(forKey: key)
        debugLog("🔐 Migrated legacy \(key) from UserDefaults to Keychain")
        return true
    }

    // MARK: - Private

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private func read(forKey key: String) -> Any? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item
        case errSecItemNotFound:
            return nil
        default:
            debugLog("🔐 Keychain read failed (\(status)) for key \(key)")
            return nil
        }
    }

    private func write(value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery(forKey: key) as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insertQuery = baseQuery(forKey: key)
            insertQuery[kSecValueData as String] = data
            insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                debugLog("🔐 Keychain add failed (\(addStatus)) for key \(key)")
            }
        default:
            debugLog("🔐 Keychain update failed (\(status)) for key \(key)")
        }
    }

    private func deleteKeychainItem(forKey key: String) {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            debugLog("🔐 Keychain delete failed (\(status)) for key \(key)")
        }
    }
}
