import Foundation
import Security

/// Minimal Keychain wrapper for the auth token (the AsyncStorage analogue, but in the
/// platform-correct place). Do not store other secrets in UserDefaults.
enum KeychainHelper {
    private static let service = "ai.abacus.app.auth"
    private static let account = "auth_token"

    static var authToken: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)
            guard let value = newValue, let data = value.data(using: .utf8) else { return }
            var attributes = base
            attributes[kSecValueData as String] = data
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }
}
