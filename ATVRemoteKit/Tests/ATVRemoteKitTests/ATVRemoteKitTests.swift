import XCTest
@testable import ATVRemoteKit

final class VarintTests: XCTestCase {
    func testEncodeDecode() {
        for value in [0, 1, 127, 128, 300, 16383, 16384, 1_000_000] {
            let encoded = Varint.encode(value)
            let decoded = Varint.decode(encoded)
            XCTAssertEqual(decoded?.value, value)
            XCTAssertEqual(decoded?.consumed, encoded.count)
        }
    }

    func testFramerReassemblesSplitMessages() {
        var framer = MessageFramer()
        let message = Data(repeating: 0xAB, count: 300)
        let framed = MessageFramer.frame(message)
        let mid = framed.count / 2
        XCTAssertEqual(framer.append(framed.prefix(mid)), [])
        XCTAssertEqual(framer.append(framed.suffix(framed.count - mid)), [message])
    }

    func testFramerSplitsCoalescedMessages() {
        var framer = MessageFramer()
        let a = Data([0x01, 0x02])
        let b = Data([0x03])
        let messages = framer.append(MessageFramer.frame(a) + MessageFramer.frame(b))
        XCTAssertEqual(messages, [a, b])
    }
}

final class PairingSecretTests: XCTestCase {
    // Expected digest generated with the Python reference implementation
    // (hashlib.sha256 over the same inputs as androidtvremote2.pairing).
    let clientModulus = Data([0xC3, 0xA1, 0xB2, 0xD4, 0xE5, 0xF6, 0x07, 0x18, 0x29, 0x3A, 0x4B, 0x5C, 0x6D, 0x7E, 0x8F, 0x90])
    let clientExponent = Data([0x01, 0x00, 0x01])
    let serverModulus = Data([0xF1, 0xE2, 0xD3, 0xC4, 0xB5, 0xA6, 0x97, 0x88, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0xAA, 0xBB])
    let serverExponent = Data([0x01, 0x00, 0x01])

    func testMatchesPythonReference() throws {
        let secret = try PairingSecret.compute(
            clientModulus: clientModulus, clientExponent: clientExponent,
            serverModulus: serverModulus, serverExponent: serverExponent,
            pairingCode: "A47F21"
        )
        XCTAssertEqual(
            secret.map { String(format: "%02x", $0) }.joined(),
            "a405bc6a88414e6d08d8bb4997a3d3db6eb1c3575da9af0a34289e8cb11d2427"
        )
    }

    func testWrongCodeThrows() {
        XCTAssertThrowsError(try PairingSecret.compute(
            clientModulus: clientModulus, clientExponent: clientExponent,
            serverModulus: serverModulus, serverExponent: serverExponent,
            pairingCode: "3A7F21"
        ))
    }
}

final class CertificateTests: XCTestCase {
    func testGeneratedCertificateRoundTrips() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)!
        let der = try SelfSignedCertificate.make(privateKey: key, commonName: "atvremote-test")
        let cert = SecCertificateCreateWithData(nil, der as CFData)
        XCTAssertNotNil(cert, "DER must parse as an X.509 certificate")

        let publicKey = SecCertificateCopyKey(cert!)
        XCTAssertNotNil(publicKey, "public key must be extractable")
        let (modulus, exponent) = try ClientIdentity.modulusExponent(of: publicKey!)
        XCTAssertEqual(modulus.count, 256, "2048-bit modulus without leading zeros")
        XCTAssertEqual(exponent, Data([0x01, 0x00, 0x01]))
    }
}
