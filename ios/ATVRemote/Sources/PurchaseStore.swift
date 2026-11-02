import Combine
import Foundation

struct PurchaseOffer: Equatable {
    let price: String
}

enum PurchaseOutcome { case purchased, cancelled, pending }

@MainActor
protocol PurchaseClient {
    func offer() async throws -> PurchaseOffer?
    func hasEntitlement() async throws -> Bool
    func purchase() async throws -> PurchaseOutcome
    func restore() async throws
    func updates() -> AsyncStream<Void>
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
        let client = client ?? RevenueCatClient()
        self.client = client
        let updates = client.updates()
        listener = Task { [weak self] in
            for await _ in updates { await self?.refreshEntitlement() }
        }
    }

    deinit { listener?.cancel() }

    @discardableResult
    func refreshEntitlement() async -> Bool {
        do {
            let unlocked = try await client.hasEntitlement()
            if unlocked && !isUnlocked { message = "すべての機能を解除しました。" }
            isUnlocked = unlocked
            return true
        } catch {
            // A network failure is not a revocation. Keep the last known state.
            message = error.localizedDescription
            return false
        }
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
                guard await refreshEntitlement() else { return }
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
            guard await refreshEntitlement() else { return }
            message = isUnlocked ? "購入を復元しました。" : "このApple Accountの購入は見つかりませんでした。"
        } catch { message = "購入を復元できませんでした。ネットワークを確認して再試行してください。" }
    }
}
