import Foundation
import Security

/// Pins the TV certificate only after the user proves possession of its pairing code.
/// An IP change or TV reset requires pairing again rather than silently trusting a new peer.
enum ServerCertificateStore {
    private static let service = "com.entaku.atvremote.tv-certificate"

    static func matches(_ certificate: Data, host: String) throws -> Bool {
        guard let expected = try load(host: host) else { return false }
        return expected == certificate
    }

    static func load(host: String) throws -> Data? {
        var query = baseQuery(host: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ATVError.keychain(status, "reading TV certificate")
        }
        return data
    }

    static func save(_ certificate: Data, host: String) throws {
        let query = baseQuery(host: host)
        let values = [kSecValueData as String: certificate]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ATVError.keychain(status, "updating TV certificate") }
        var item = query
        item[kSecValueData as String] = certificate
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw ATVError.keychain(added, "saving TV certificate") }
    }

    private static func baseQuery(host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host.lowercased(),
            kSecAttrSynchronizable as String: false
        ]
    }
}
