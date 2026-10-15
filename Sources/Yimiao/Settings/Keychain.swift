import Foundation
import Security

/// The API key lives in the login keychain rather than in a preferences file.
enum Keychain {
    private static func query(for provider: AIProvider) -> [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.github.hannah-bbbb.yimiao",
        kSecAttrAccount as String: provider.keychainAccount,
    ] }

    static func load(for provider: AIProvider) -> String {
        var request = query(for: provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ value: String, for provider: AIProvider) {
        let query = query(for: provider)
        guard !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "译喵 · \(provider.name) API Key"
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
