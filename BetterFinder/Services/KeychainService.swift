import Foundation
import Security

enum KeychainService {
    private static let servicePrefix = "com.betterfinder.network."

    static func save(username: String, password: String, for hostname: String) {
        let service = servicePrefix + hostname.lowercased()

        // Delete existing entry first
        delete(for: hostname)

        guard let passwordData = password.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: passwordData,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for hostname: String) -> NetworkCredentials? {
        let service = servicePrefix + hostname.lowercased()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let dict = result as? [String: Any],
              let username = dict[kSecAttrAccount as String] as? String,
              let passwordData = dict[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8)
        else { return nil }

        return NetworkCredentials(username: username, password: password, saveToKeychain: true)
    }

    static func delete(for hostname: String) {
        let service = servicePrefix + hostname.lowercased()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
