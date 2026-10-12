import Foundation
import Observation
import StoreKit

/// Pro unlock as a one-time, non-consumable in-app purchase (StoreKit 2).
///
/// Create a non-consumable product with `productID` in App Store Connect, or
/// test locally with a StoreKit configuration file in an Xcode scheme.
@MainActor
@Observable
final class ProStore {
    static let productID = "com.chenhuicui.screenmonitor.pro"

    /// Pro is currently free for everyone. Set to false to sell it as an
    /// in-app purchase; the StoreKit code below then takes over.
    static let unlockedForEveryone = true

    private(set) var product: Product?
    private(set) var hasPurchased = false
    private(set) var isLoading = false
    var message: String?

    /// Debug-only override (`--pro` launch argument) to work on Pro screens.
    let developerOverride: Bool

    @ObservationIgnored private var updates: Task<Void, Never>?

    var isPro: Bool { Self.unlockedForEveryone || hasPurchased || developerOverride }

    init(developerOverride: Bool = false) {
        self.developerOverride = developerOverride
    }

    func start() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            message = "Could not reach the App Store: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        hasPurchased = owned
    }

    func purchase() async {
        guard let product else {
            message = "Screen Monitor Pro is not available yet. Set up \(Self.productID) in App Store Connect."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlements()
            case .success(.unverified(_, let error)):
                message = "The purchase could not be verified: \(error.localizedDescription)"
            case .pending:
                message = "The payment is pending."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
        } catch {
            message = "Restore failed: \(error.localizedDescription)"
        }
        await refreshEntitlements()
        if !hasPurchased, message == nil {
            message = "No previous purchase was found for this Apple ID."
        }
    }
}
