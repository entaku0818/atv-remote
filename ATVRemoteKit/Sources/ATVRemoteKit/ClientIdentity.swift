import Foundation
import Security

public enum ATVError: Error, LocalizedError {
    case keychain(OSStatus, String)
    case certificateCreation(String)
    case connectionClosed(String)
    case pairingFailed(String)
    case invalidPairingCode(String)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status, let msg): return "Keychain error \(status): \(msg)"
        case .certificateCreation(let msg): return "Certificate creation failed: \(msg)"
        case .connectionClosed(let msg): return "Connection closed: \(msg)"
        case .pairingFailed(let msg): return "Pairing failed: \(msg)"
        case .invalidPairingCode(let msg): return "Invalid pairing code: \(msg)"
        }
    }
}

/// The client's TLS identity (RSA key + self-signed certificate), persisted in the Keychain.
/// The Android TV learns this certificate during pairing and trusts it afterwards,
/// so the same identity must be reused across connections.
public struct ClientIdentity {
    public let identity: SecIdentity
    public let certificate: SecCertificate
    public static let defaultLabel = "atv-remote-client"

    public init(identity: SecIdentity, certificate: SecCertificate) {
        self.identity = identity
        self.certificate = certificate
    }

    /// Loads the identity from the Keychain, generating key + certificate on first use.
    public static func loadOrCreate(label: String = defaultLabel, commonName: String = "atvremote") throws -> ClientIdentity {
        if let existing = try? load(commonName: commonName) { return existing }
        try create(label: label, commonName: commonName)
        return try load(commonName: commonName)
    }

    public static func load(commonName: String) throws -> ClientIdentity {
        // Enumerate identities and match by the certificate's subject CN.
        // (Matching by kSecAttrLabel is unreliable: the macOS legacy keychain
        // ignores the label passed to SecItemAdd for certificates and derives
        // it from the CN instead.)
        let idQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var idResult: CFTypeRef?
        let status = SecItemCopyMatching(idQuery as CFDictionary, &idResult)
        guard status == errSecSuccess, let identities = idResult as? [SecIdentity] else {
            throw ATVError.keychain(status, "no identities in keychain")
        }
        for identity in identities {
            var idCert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &idCert) == errSecSuccess,
                  let idCert else { continue }
            if SecCertificateCopySubjectSummary(idCert) as String? == commonName {
                return ClientIdentity(identity: identity, certificate: idCert)
            }
        }
        throw ATVError.keychain(errSecItemNotFound, "identity with CN '\(commonName)' not found")
    }

    public static func create(label: String, commonName: String) throws {
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(label.utf8),
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &error) else {
            throw ATVError.certificateCreation("key generation: \(error!.takeRetainedValue())")
        }
        let certDER = try SelfSignedCertificate.make(privateKey: privateKey, commonName: commonName)
        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw ATVError.certificateCreation("SecCertificateCreateWithData failed")
        }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ATVError.keychain(status, "adding certificate")
        }
    }

    public static func delete(label: String = defaultLabel) {
        SecItemDelete([
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(label.utf8),
        ] as CFDictionary)
    }

    /// Modulus and exponent of this client's public key (leading zeros stripped),
    /// as needed for the pairing secret.
    public func publicKeyModulusExponent() throws -> (modulus: Data, exponent: Data) {
        guard let key = SecCertificateCopyKey(certificate) else {
            throw ATVError.certificateCreation("cannot extract public key from client certificate")
        }
        return try Self.modulusExponent(of: key)
    }

    static func modulusExponent(of publicKey: SecKey) throws -> (modulus: Data, exponent: Data) {
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw ATVError.certificateCreation("export public key: \(error!.takeRetainedValue())")
        }
        guard let parsed = ASN1.parsePKCS1RSAPublicKey(der) else {
            throw ATVError.certificateCreation("cannot parse PKCS#1 RSAPublicKey")
        }
        return parsed
    }
}

/// Builds a self-signed X.509 v3 certificate mirroring what androidtvremote2
/// generates (CN, 10-year validity, CA basic constraint, SAN).
public enum SelfSignedCertificate {
    public static func make(privateKey: SecKey, commonName: String) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ATVError.certificateCreation("cannot derive public key")
        }
        var error: Unmanaged<CFError>?
        guard let publicKeyPKCS1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw ATVError.certificateCreation("export public key: \(error!.takeRetainedValue())")
        }

        let sha256WithRSA = ASN1.sequence([
            ASN1.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]),
            ASN1.null(),
        ])
        let rsaEncryption = ASN1.sequence([
            ASN1.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]),
            ASN1.null(),
        ])
        let name = ASN1.sequence([
            ASN1.set([
                ASN1.sequence([
                    ASN1.oid([0x55, 0x04, 0x03]), // commonName
                    ASN1.utf8String(commonName),
                ]),
            ]),
        ])
        let now = Date()
        let validity = ASN1.sequence([
            ASN1.utcTime(now.addingTimeInterval(-86400)),
            ASN1.utcTime(now.addingTimeInterval(10 * 365 * 86400)),
        ])
        let spki = ASN1.sequence([
            rsaEncryption,
            ASN1.bitString(publicKeyPKCS1),
        ])
        let extensions = ASN1.contextConstructed(3, ASN1.sequence([
            ASN1.sequence([ // basicConstraints CA:TRUE, pathLen 0
                ASN1.oid([0x55, 0x1D, 0x13]),
                ASN1.octetString(ASN1.sequence([ASN1.boolean(true), ASN1.integer(0)])),
            ]),
            ASN1.sequence([ // subjectAltName dNSName
                ASN1.oid([0x55, 0x1D, 0x11]),
                ASN1.octetString(ASN1.sequence([
                    ASN1.contextPrimitive(2, Data(commonName.utf8)),
                ])),
            ]),
        ]))
        let tbs = ASN1.sequence([
            ASN1.contextConstructed(0, ASN1.integer(2)), // version v3
            ASN1.integer(1000),
            sha256WithRSA,
            name,
            validity,
            name,
            spki,
            extensions,
        ])
        guard let signature = SecKeyCreateSignature(
            privateKey, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &error
        ) as Data? else {
            throw ATVError.certificateCreation("signing: \(error!.takeRetainedValue())")
        }
        return ASN1.sequence([tbs, sha256WithRSA, ASN1.bitString(signature)])
    }
}
