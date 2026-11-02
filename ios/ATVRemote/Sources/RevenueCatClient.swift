import Foundation
import RevenueCat

@MainActor
final class RevenueCatClient: PurchaseClient {
    static let productID = "com.entaku.pocketremote.fullunlock"
    static let entitlementID = "full_unlock"
    private let purchases: Purchases?
    private var product: StoreProduct?

    init(apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicAPIKey") as? String) {
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              key.hasPrefix("appl_"), key.count > 5 else {
            purchases = nil
            return
        }
        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: key)
        }
        purchases = Purchases.shared
    }

    private func configured() throws -> Purchases {
        guard let purchases else { throw PurchaseError.unavailable }
        return purchases
    }

    func offer() async throws -> PurchaseOffer? {
        let sdk = try configured()
        product = await sdk.products([Self.productID]).first { $0.productIdentifier == Self.productID }
        return product.map { PurchaseOffer(price: $0.localizedPriceString) }
    }

    func hasEntitlement() async throws -> Bool {
        let info = try await configured().customerInfo()
        return info.entitlements[Self.entitlementID]?.isActive == true
    }

    func purchase() async throws -> PurchaseOutcome {
        guard let product else { throw PurchaseError.unavailable }
        do {
            let result = try await configured().purchase(product: product)
            return result.userCancelled ? .cancelled : .purchased
        } catch {
            switch (error as NSError).code {
            case ErrorCode.purchaseCancelledError.rawValue: return .cancelled
            case ErrorCode.paymentPendingError.rawValue: return .pending
            default: throw error
            }
        }
    }

    func restore() async throws {
        _ = try await configured().restorePurchases()
    }

    func updates() -> AsyncStream<Void> {
        guard let purchases else { return AsyncStream { $0.finish() } }
        let stream = purchases.customerInfoStream
        return AsyncStream { continuation in
            let task = Task {
                for await _ in stream {
                    guard !Task.isCancelled else { break }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
