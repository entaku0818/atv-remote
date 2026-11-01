import Security
import XCTest
@testable import ATVRemoteKit

final class KeychainIntegrationTests: XCTestCase {
    func testClientIdentitySurvivesReload() throws {
        let label = "atvremote-test-\(UUID())"
        defer { ClientIdentity.delete(label: label) }
        let original = try ClientIdentity.loadOrCreate(label: label, commonName: label)
        let restored = try ClientIdentity.loadOrCreate(label: label, commonName: label)
        XCTAssertEqual(SecCertificateCopyData(original.certificate) as Data,
                       SecCertificateCopyData(restored.certificate) as Data)
    }

    func testTVPinRejectsUnknownOrChangedCertificate() throws {
        let host = "test-\(UUID())"
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.entaku.atvremote.tv-certificate",
                kSecAttrAccount as String: host.lowercased()
            ] as CFDictionary)
        }
        let certificate = Data([1, 2, 3])
        XCTAssertFalse(try ServerCertificateStore.matches(certificate, host: host))
        try ServerCertificateStore.save(certificate, host: host)
        XCTAssertTrue(try ServerCertificateStore.matches(certificate, host: host))
        XCTAssertFalse(try ServerCertificateStore.matches(Data([4, 5, 6]), host: host))
        XCTAssertFalse(try ServerCertificateStore.matches(certificate, host: "another-\(host)"))
        try ServerCertificateStore.save(Data([4, 5, 6]), host: host)
        XCTAssertFalse(try ServerCertificateStore.matches(certificate, host: host))
    }
}
