import Combine
import Foundation
import StoreKit

struct PurchaseOffer: Equatable {
    let price: String
}

enum PurchaseOutcome { case purchased, cancelled, pending }

@MainActor
protocol PurchaseClient {
    func offer() async throws -> PurchaseOffer?
    func hasEntitlement() async -> Bool
    func purchase() async throws -> PurchaseOutcome
    func restore() async throws
    func updates() -> AsyncStream<Void>
}

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

enum PurchaseError: LocalizedError {
    case unavailable, unverified
    var errorDescription: String? {
        switch self {
        case .unavailable: return "購入情報を取得できませんでした。時間をおいて再試行してください。"
        case .unverified: return "購入を確認できませんでした。購入の復元をお試しください。"
        }
    }
}

@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var offer: PurchaseOffer?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    private let client: any PurchaseClient
    private var listener: Task<Void, Never>?

    init(client: (any PurchaseClient)? = nil) {
        let client = client ?? StoreKitClient()
        self.client = client
        let updates = client.updates()
        listener = Task { [weak self] in
            for await _ in updates { await self?.refreshEntitlement() }
        }
    }

    deinit { listener?.cancel() }

    func refreshEntitlement() async {
        let unlocked = await client.hasEntitlement()
        if unlocked && !isUnlocked { message = "すべての機能を解除しました。" }
        isUnlocked = unlocked
    }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await refreshEntitlement()
        offer = nil
        do {
            offer = try await client.offer()
            message = offer == nil ? PurchaseError.unavailable.localizedDescription : nil
        } catch { message = error.localizedDescription }
    }

    func purchase() async {
        guard !isBusy, offer != nil, !isUnlocked else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await client.purchase() {
            case .purchased:
                await refreshEntitlement()
                message = isUnlocked ? "すべての機能を解除しました。" : "購入確認中です。購入の復元をお試しください。"
            case .pending: message = "購入は承認待ちです。承認後に自動で反映されます。"
            case .cancelled: break
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await client.restore()
            await refreshEntitlement()
            message = isUnlocked ? "購入を復元しました。" : "このApple Accountの購入は見つかりませんでした。"
        } catch { message = "購入を復元できませんでした。ネットワークを確認して再試行してください。" }
    }
}
