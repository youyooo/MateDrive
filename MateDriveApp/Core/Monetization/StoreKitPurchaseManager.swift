import Combine
import StoreKit

@MainActor
final class StoreKitPurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var entitlement = ProEntitlementSnapshot.none
    @Published private(set) var lastErrorMessage: String?

    private let catalog: StoreProductCatalog
    private var transactionUpdatesTask: Task<Void, Never>?

    init(catalog: StoreProductCatalog = .mateDrive) {
        self.catalog = catalog
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { [weak self] in
            await self?.refresh()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refresh() async {
        async let productRefresh: Void = refreshProducts()
        async let entitlementRefresh: Void = refreshEntitlements()
        _ = await (productRefresh, entitlementRefresh)
    }

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    lastErrorMessage = "The purchase could not be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                lastErrorMessage = nil
                return true
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshProducts() async {
        do {
            products = try await Product.products(for: catalog.productIDs)
                .sorted { $0.price < $1.price }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var hasLifetime = false
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.revocationDate == nil else {
                continue
            }
            if transaction.productID == catalog.lifetimeID {
                hasLifetime = true
            } else if catalog.subscriptionIDs.contains(transaction.productID) {
                hasActiveSubscription = true
            }
        }

        entitlement = ProEntitlementSnapshot(
            hasLifetime: hasLifetime,
            hasActiveSubscription: hasActiveSubscription
        )
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }
            guard case let .verified(transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }
}
