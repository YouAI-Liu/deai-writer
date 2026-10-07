import Foundation
import Security

/// Where API keys live. `set(nil)` deletes.
protocol SecretStore {
    func get(_ account: String) -> String?
    func set(_ value: String?, for account: String)
}

/// macOS Keychain (generic-password items). The classic file keychain is
/// used deliberately — kSecUseDataProtectionKeychain would require
/// entitlements this ad-hoc/dev-signed app does not have.
final class KeychainSecretStore: SecretStore {
    private let service =
        "\(Bundle.main.bundleIdentifier ?? "com.local.deai").provider"

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for account: String) {
        let q = query(account)
        guard let value, !value.isEmpty else {
            SecItemDelete(q as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            q as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

/// Test double — nothing leaves the process.
final class InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]
    func get(_ account: String) -> String? { values[account] }
    func set(_ value: String?, for account: String) {
        values[account] = value
    }
}
