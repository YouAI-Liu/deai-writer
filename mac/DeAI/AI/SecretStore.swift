import Foundation
import OSLog
import Security

/// Where API keys live. `set(nil)` deletes.
protocol SecretStore {
    func get(_ account: String) -> String?
    func set(_ value: String?, for account: String)
}

/// What to do with a SecureField draft. `onCommit` also fires when the field
/// merely loses focus — with the draft already cleared after a save that
/// would feed an empty value into `set(_:for:)` and wipe the stored key, so
/// empty/whitespace drafts are ignored and never reach the store.
enum KeyAction: Equatable {
    case save(String)
    case ignore

    init(draft: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        self = trimmed.isEmpty ? .ignore : .save(trimmed)
    }
}

/// macOS Keychain (generic-password items). The classic file keychain is
/// used deliberately — kSecUseDataProtectionKeychain would require
/// entitlements this ad-hoc/dev-signed app does not have.
final class KeychainSecretStore: SecretStore {
    private let log = Logger(
        subsystem: "com.local.deai", category: "secrets"
    )
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
            let st = SecItemDelete(q as CFDictionary)
            if st != errSecSuccess && st != errSecItemNotFound {
                log.error(
                    "SecItemDelete failed: \(st, privacy: .public)"
                )
            }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            q as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            var add = q
            add[kSecValueData as String] = data
            let st = SecItemAdd(add as CFDictionary, nil)
            if st != errSecSuccess {
                log.error("SecItemAdd failed: \(st, privacy: .public)")
            }
        default:
            log.error("SecItemUpdate failed: \(status, privacy: .public)")
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
