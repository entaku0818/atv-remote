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
///
/// The password is random per machine and kept next to the keychain in
/// `~/.atvremote/cli.keychain.password` (mode 0600). Keychains created by older
/// versions used a fixed password; they are re-keyed in place on first use, so the
/// existing client identity (and the TV's pairing with it) is kept.
enum MacKeychainIdentity {
    static let commonName = "atvremote"
    /// Password used by versions before the per-machine random password.
    private static let legacyPassword = "atvremote"

    static var directory: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".atvremote")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    static var keychainPath: String {
        (directory as NSString).appendingPathComponent("cli.keychain")
    }

    static var passwordPath: String {
        (directory as NSString).appendingPathComponent("cli.keychain.password")
    }

    static func loadOrCreate() throws -> ClientIdentity {
        let password = try keychainPassword()
        let keychain = try openOrCreateKeychain(password: password)
        if let existing = identity(in: keychain) {
            return existing
        }
        try createKeyAndCertificate(in: keychain)
        openPartitionList(password: password)
        guard let created = identity(in: keychain) else {
            throw ATVError.certificateCreation("identity not found after creation")
        }
        return created
    }

    // MARK: Keychain lifecycle

    /// Returns this machine's keychain password, creating it (and re-keying a
    /// keychain that still uses the legacy password) when missing.
    private static func keychainPassword() throws -> String {
        if let saved = try? String(contentsOfFile: passwordPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            return saved
        }
        let password = try randomPassword()
        if FileManager.default.fileExists(atPath: keychainPath) {
            try rekeyLegacyKeychain(to: password)
        }
        try savePassword(password)
        return password
    }

    private static func randomPassword() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ATVError.keychain(status, "generating keychain password")
        }
        return Data(bytes).base64EncodedString()
    }

    private static func savePassword(_ password: String) throws {
        let created = FileManager.default.createFile(
            atPath: passwordPath, contents: Data(password.utf8), attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw ATVError.keychain(errSecIO, "writing \(passwordPath)")
        }
    }

    /// Changes the password of a keychain created with the legacy fixed password.
    private static func rekeyLegacyKeychain(to password: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["set-keychain-password", "-o", legacyPassword, "-p", password, keychainPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ATVError.keychain(
                errSecAuthFailed,
                "could not re-key \(keychainPath); delete it to start over (the TV will ask to pair again)"
            )
        }
    }

    private static func openOrCreateKeychain(password: String) throws -> SecKeychain {
        let path = keychainPath
        var keychain: SecKeychain?
        var status = SecKeychainOpen(path, &keychain)
        if status == errSecSuccess, let keychain,
           SecKeychainUnlock(keychain, UInt32(password.utf8.count), password, true) == errSecSuccess {
            return keychain
        }
        status = SecKeychainCreate(
            path, UInt32(password.utf8.count), password, false, nil, &keychain
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
    private static func openPartitionList(password: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "set-key-partition-list",
            "-S", "apple-tool:,apple:,unsigned:",
            "-s", "-k", password,
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
