import ATVRemoteKit
import Foundation
import Security

/// macOS-only client identity backed by a dedicated file keychain with a known
/// password. The iOS app uses the app-scoped keychain (no prompts), but an
/// ad-hoc-signed CLI cannot use the data-protection keychain (errSecMissingEntitlement),
/// and the login keychain prompts for private-key access on every rebuild.
///
/// A dedicated keychain whose password we control lets us open the key's
/// partition list non-interactively, so TLS signing never triggers a UI prompt.
/// The keychain file is reused across runs so pairing persists.
enum MacKeychainIdentity {
    static let keychainPassword = "atvremote"
    static let commonName = "atvremote"

    static var keychainPath: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".atvremote")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("cli.keychain")
    }

    static func loadOrCreate() throws -> ClientIdentity {
        let keychain = try openOrCreateKeychain()
        if let existing = identity(in: keychain) {
            return existing
        }
        try createKeyAndCertificate(in: keychain)
        openPartitionList()
        guard let created = identity(in: keychain) else {
            throw ATVError.certificateCreation("identity not found after creation")
        }
        return created
    }

    // MARK: Keychain lifecycle

    private static func openOrCreateKeychain() throws -> SecKeychain {
        let path = keychainPath
        var keychain: SecKeychain?
        var status = SecKeychainOpen(path, &keychain)
        if status == errSecSuccess, let keychain,
           SecKeychainUnlock(keychain, UInt32(keychainPassword.utf8.count), keychainPassword, true) == errSecSuccess {
            return keychain
        }
        status = SecKeychainCreate(
            path, UInt32(keychainPassword.utf8.count), keychainPassword, false, nil, &keychain
        )
        guard status == errSecSuccess, let keychain else {
            throw ATVError.keychain(status, "creating CLI keychain")
        }
        return keychain
    }

    private static func createKeyAndCertificate(in keychain: SecKeychain) throws {
        var error: Unmanaged<CFError>?
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecUseKeychain as String: keychain,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrLabel as String: commonName,
            ],
        ]
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw ATVError.certificateCreation("key generation: \(error!.takeRetainedValue())")
        }
        let der = try SelfSignedCertificate.make(privateKey: privateKey, commonName: commonName)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw ATVError.certificateCreation("SecCertificateCreateWithData failed")
        }
        let status = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecUseKeychain as String: keychain,
        ] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ATVError.keychain(status, "adding certificate to CLI keychain")
        }
    }

    /// Grants non-interactive access to the private key for signing.
    private static func openPartitionList() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "set-key-partition-list",
            "-S", "apple-tool:,apple:,unsigned:",
            "-s", "-k", keychainPassword,
            keychainPath,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static func identity(in keychain: SecKeychain) -> ClientIdentity? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassIdentity,
            kSecMatchSearchList as String: [keychain],
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let identities = result as? [SecIdentity] else {
            return nil
        }
        for identity in identities {
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { continue }
            if SecCertificateCopySubjectSummary(cert) as String? == commonName {
                return ClientIdentity(identity: identity, certificate: cert)
            }
        }
        return nil
    }
}
