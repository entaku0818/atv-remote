// Test-only Apple StoreKit fixture; does not validate RevenueCat.
import StoreKit
@testable import ATVRemote

@MainActor
final class StoreKitClient: PurchaseClient {
    static let productID = "com.entaku.pocketremote.fullunlock"
    private var product: Product?

    func offer() async throws -> PurchaseOffer? {
        product = try await Product.products(for: [Self.productID]).first { $0.type == .nonConsumable }
        return product.map { PurchaseOffer(price: $0.displayPrice) }
    }

    func hasEntitlement() async -> Bool {
        for await verification in Transaction.currentEntitlements {
            if case .verified(let transaction) = verification,
               transaction.productID == Self.productID, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func purchase() async throws -> PurchaseOutcome {
        guard let product else { throw PurchaseError.unavailable }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification,
                  transaction.productID == Self.productID, transaction.revocationDate == nil else {
                throw PurchaseError.unverified
            }
            await transaction.finish()
            return .purchased
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: throw PurchaseError.unavailable
        }
    }

    func restore() async throws { try await AppStore.sync() }

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard case .verified(let transaction) = verification,
                          transaction.productID == Self.productID else { continue }
                    continuation.yield(())
                    await transaction.finish()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
