import XCTest
@testable import ATVRemote

final class RemoteInputTests: XCTestCase {
    func testPairingCodeNormalizesAndLimitsHexadecimal() {
        XCTAssertEqual(RemoteInput.pairingCode(" a4-7f21\n"), "A47F21")
        XCTAssertEqual(RemoteInput.pairingCode("GHIxyz!"), "")
        XCTAssertEqual(RemoteInput.pairingCode("1234567"), "123456")
    }

    func testManualAddressRequiresAnIP() {
        XCTAssertEqual(RemoteInput.host(" 192.168.1.2\n"), "192.168.1.2")
        XCTAssertNotNil(RemoteInput.host("2001:db8::1"))
        XCTAssertNil(RemoteInput.host("192.168.1.999"))
        XCTAssertNil(RemoteInput.host("https://example.com"))
        XCTAssertNil(RemoteInput.host(""))
    }

    func testLinksRejectCredentialsAndIncompleteTVerPaths() {
        XCTAssertNotNil(RemoteInput.linkError("file:///secret"))
        XCTAssertNotNil(RemoteInput.linkError("https://user:password@example.com"))
        XCTAssertNotNil(RemoteInput.linkError("https://tver.jp/episodes/"))
        XCTAssertNotNil(RemoteInput.linkError("https://tver.jp/"))
        XCTAssertNil(RemoteInput.linkError("https://tver.jp/episodes/abcd"))
        XCTAssertNil(RemoteInput.linkError("https://not-tver.jp/"))
        XCTAssertNil(RemoteInput.linkError("https://example.com/video"))
    }
}

@MainActor
final class AppBehaviorTests: XCTestCase {
    func testPrivacyAndLicenseResourcesAreBundled() throws {
        for name in ["ATVRemote-LICENSE", "SwiftProtobuf-LICENSE"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "txt"))
            XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).isEmpty)
        }
        let privacy = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: privacy)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
    }

    func testHistoryDeduplicatesLimitsPersistsAndClears() throws {
        let suite = "ATVRemoteTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = LinkHistory(defaults: defaults)
        for index in 0..<35 { history.add("https://example.com/\(index)") }
        XCTAssertEqual(history.items.count, 30)
        history.add("https://example.com/10")
        XCTAssertEqual(history.items.first?.url, "https://example.com/10")
        XCTAssertEqual(history.items.count, 30)
        XCTAssertEqual(LinkHistory(defaults: defaults).items, history.items)
        history.clear()
        XCTAssertTrue(LinkHistory(defaults: defaults).items.isEmpty)
    }

    func testDisconnectedRemoteCannotClaimSendSuccess() {
        let model = RemoteViewModel(host: "192.0.2.1")
        model.send(.keycodeDpadUp, label: "上")
        XCTAssertEqual(model.result?.kind, .failure)
        model.launch("https://example.com/video")
        XCTAssertEqual(model.result?.kind, .failure)
    }

    func testDisconnectResetsPhaseAndPairingValidation() {
        let model = RemoteViewModel(host: "192.0.2.1")
        model.pairingCode = "ab12xy34ZZ"
        XCTAssertEqual(model.pairingCode, "AB1234")
        model.phase = .connected
        model.disconnect()
        XCTAssertEqual(model.phase, .idle)
    }
}
