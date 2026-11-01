import StoreKit
import StoreKitTest
import XCTest
@testable import ATVRemote

@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    func testLocalNonConsumablePurchaseAndRefund() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Local", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let client = StoreKitClient()
        let offer = try await client.offer()
        XCTAssertNotNil(offer)
        let initiallyEntitled = await client.hasEntitlement()
        XCTAssertFalse(initiallyEntitled)
        let result = try await client.purchase()
        guard case .purchased = result else { return XCTFail("Expected completed purchase") }
        let entitled = await client.hasEntitlement()
        XCTAssertTrue(entitled)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        // StoreKit propagates refund notifications asynchronously.
        var refunded = false
        for _ in 0..<50 {
            if !(await client.hasEntitlement()) { refunded = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(refunded, "Refund must remove the verified entitlement")
    }
}
