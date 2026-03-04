import Foundation
import StoreKit
import Observation

@MainActor
@Observable
public final class StoreService {

    // MARK: - State

    public var products: [Product] = []
    public var isProUser: Bool = false
    public var purchaseError: String?

    // MARK: - Private

    private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    private static let productIDs: Set<String> = [
        "hellbent.pro.monthly",
        "hellbent.pro.yearly"
    ]

    // MARK: - Init

    public init() {
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.checkEntitlements()
                }
            }
        }
        Task { await checkEntitlements() }
        Task { await loadProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    public func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("[StoreService] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    @discardableResult
    public func purchase(_ product: Product) async throws -> Bool {
        purchaseError = nil

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                purchaseError = "Purchase could not be verified."
                return false
            }
            await transaction.finish()
            await checkEntitlements()
            return true

        case .userCancelled:
            return false

        case .pending:
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore

    public func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlements()
    }

    // MARK: - Entitlements

    public func checkEntitlements() async {
        var hasEntitlement = false

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if Self.productIDs.contains(transaction.productID) {
                    hasEntitlement = true
                    break
                }
            }
        }

        isProUser = hasEntitlement
    }
}
