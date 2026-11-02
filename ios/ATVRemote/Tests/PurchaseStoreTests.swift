import XCTest
@testable import ATVRemote

@MainActor
final class PurchaseStoreTests: XCTestCase {
    func testPurchaseUnlocksOnlyAfterEntitlementVerification() async {
        let client = FakePurchaseClient()
        let store = PurchaseStore(client: client)
        await store.load()
        XCTAssertFalse(store.isUnlocked)
        await store.purchase()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertFalse(store.isBusy)
    }

    func testCancelledAndPendingPurchasesDoNotUnlock() async {
        for outcome in [PurchaseOutcome.cancelled, .pending] {
            let client = FakePurchaseClient()
            client.outcome = outcome
            let store = PurchaseStore(client: client)
            await store.load()
            await store.purchase()
            XCTAssertFalse(store.isUnlocked)
            XCTAssertFalse(store.isBusy)
        }
    }

    func testVerificationFailureDoesNotUnlock() async {
        let client = FakePurchaseClient()
        client.purchaseError = PurchaseError.unverified
        let store = PurchaseStore(client: client)
        await store.load()
        await store.purchase()
        XCTAssertFalse(store.isUnlocked)
        XCTAssertNotNil(store.message)
    }

    func testProductFailureDoesNotRemoveExistingEntitlement() async {
        let client = FakePurchaseClient()
        client.entitled = true
        client.offerError = PurchaseError.unavailable
        let store = PurchaseStore(client: client)
        await store.load()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertNil(store.offer)
    }

    func testRestoreAndRevocationRefresh() async {
        let client = FakePurchaseClient()
        let store = PurchaseStore(client: client)
        client.entitled = true
        await store.restore()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertEqual(client.restoreCount, 1)
        client.entitled = false
        await store.refreshEntitlement()
        XCTAssertFalse(store.isUnlocked)
    }

    func testRestoreFailureLeavesStatusAndAllowsRetry() async {
        let client = FakePurchaseClient()
        client.restoreError = PurchaseError.unavailable
        let store = PurchaseStore(client: client)
        await store.restore()
        XCTAssertFalse(store.isBusy)
        XCTAssertNotNil(store.message)
        client.restoreError = nil
        client.entitled = true
        await store.restore()
        XCTAssertTrue(store.isUnlocked)
    }

    func testTransactionUpdatesUnlockPendingPurchaseAndRevokeRefund() async throws {
        let client = FakePurchaseClient()
        let store = PurchaseStore(client: client)
        await store.load()
        client.entitled = true
        client.continuation?.yield(())
        for _ in 0..<50 where !store.isUnlocked { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.isUnlocked)
        client.entitled = false
        client.continuation?.yield(())
        for _ in 0..<50 where store.isUnlocked { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isUnlocked)
    }

    func testNetworkFailurePreservesLastKnownEntitlement() async {
        let client = FakePurchaseClient()
        client.entitled = true
        let store = PurchaseStore(client: client)
        await store.refreshEntitlement()
        client.entitlementError = PurchaseError.unavailable
        client.entitled = false
        await store.refreshEntitlement()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertNotNil(store.message)
        client.entitlementError = nil
        await store.refreshEntitlement()
        XCTAssertFalse(store.isUnlocked)
    }

    func testMissingRevenueCatConfigurationCannotUnlockOrOfferPurchase() async {
        for key in ["", "test_example", "sk_secret", "$(REVENUECAT_PUBLIC_API_KEY)"] {
            let store = PurchaseStore(client: RevenueCatClient(apiKey: key))
            await store.load()
            XCTAssertFalse(store.isUnlocked)
            XCTAssertNil(store.offer)
            XCTAssertNotNil(store.message)
            await store.restore()
            XCTAssertFalse(store.isUnlocked)
        }
    }

    func testMissingProductCannotStartPurchase() async {
        let client = FakePurchaseClient()
        client.product = nil
        let store = PurchaseStore(client: client)
        await store.load()
        await store.purchase()
        XCTAssertEqual(client.purchaseCount, 0)
        XCTAssertFalse(store.isUnlocked)
    }
}

@MainActor
private final class FakePurchaseClient: PurchaseClient {
    var continuation: AsyncStream<Void>.Continuation?
    var product: PurchaseOffer? = PurchaseOffer(price: "¥480")
    var entitled = false
    var outcome = PurchaseOutcome.purchased
    var entitlementError: Error?
    var offerError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var purchaseCount = 0
    var restoreCount = 0
    func offer() async throws -> PurchaseOffer? {
        if let offerError { throw offerError }
        return product
    }
    func hasEntitlement() async throws -> Bool {
        if let entitlementError { throw entitlementError }
        return entitled
    }
    func purchase() async throws -> PurchaseOutcome {
        purchaseCount += 1
        if let purchaseError { throw purchaseError }
        if case .purchased = outcome { entitled = true }
        return outcome
    }
    func restore() async throws {
        restoreCount += 1
        if let restoreError { throw restoreError }
    }
    func updates() -> AsyncStream<Void> { AsyncStream { continuation = $0 } }
}
