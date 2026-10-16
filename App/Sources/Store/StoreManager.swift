import Foundation
import StoreKit
import VocabCore
import WidgetKit

/// StoreKit 2 wrapper for the two Vocabi Pro subscriptions. Publishes products, purchase state and
/// the current `ProEntitlement`, which is mirrored to the App Group on every change so the widget
/// can read it without StoreKit.
@MainActor
final class StoreManager: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    @Published private(set) var products: [ProProduct: Product] = [:]
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var entitlement: ProEntitlement
    /// Whether the user can still get the introductory free trial (one per subscription group).
    @Published private(set) var isEligibleForTrial = true
    @Published private(set) var purchasing: ProProduct?
    @Published private(set) var isRestoring = false
    /// User-facing error from the last purchase / restore attempt.
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var started = false

    init() {
        entitlement = ProEntitlement.load()
        updatesTask = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    /// Pro features unlocked: active subscription/trial, or a debug dev token.
    var isPro: Bool { entitlement.isActive(at: Date()) || DevToken.current != nil }

    var hasRealSubscription: Bool { entitlement.isActive(at: Date()) }

    /// Loads products and entitlements once per launch.
    func start() async {
        guard !started else { return }
        started = true
        await refreshEntitlement()
        await loadProducts()
    }

    // MARK: Products

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: ProProduct.allIDs)
            var map: [ProProduct: Product] = [:]
            for p in loaded { if let id = ProProduct(rawValue: p.id) { map[id] = p } }
            products = map
            loadState = map.count == ProProduct.allCases.count ? .loaded : .failed
            if let sub = map.values.first?.subscription {
                isEligibleForTrial = await sub.isEligibleForIntroOffer
            }
        } catch {
            loadState = .failed
        }
    }

    func price(for product: ProProduct) -> Decimal { products[product]?.price ?? product.fallbackPrice }

    func displayPrice(for product: ProProduct) -> String { products[product]?.displayPrice ?? product.fallbackDisplayPrice }

    /// "Save 16%" figure computed from the live prices (falls back to the US list prices).
    var monthlySavingsPercent: Int {
        ProPricing.monthlySavingsPercent(weekly: price(for: .weekly), monthly: price(for: .monthly))
    }

    /// Free-trial length in days for a product, or `nil` when the user can't get a trial.
    func trialDays(for product: ProProduct) -> Int? {
        guard isEligibleForTrial else { return nil }
        guard let p = products[product] else { return 3 } // fallback display (docs/PRICING.md)
        guard let offer = p.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let v = offer.period.value
        switch offer.period.unit {
        case .day: return v
        case .week: return v * 7
        case .month: return v * 30
        case .year: return v * 365
        @unknown default: return v
        }
    }

    // MARK: Purchase / restore

    /// Returns true when the purchase completed and Pro is active.
    @discardableResult
    func purchase(_ product: ProProduct) async -> Bool {
        errorMessage = nil
        if products[product] == nil { await loadProducts() }
        guard let p = products[product] else {
            errorMessage = String(localized: "The App Store is unavailable right now. Please try again later.")
            return false
        }
        purchasing = product
        defer { purchasing = nil }
        do {
            switch try await p.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = String(localized: "The purchase couldn't be verified.")
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                return hasRealSubscription
            case .pending:
                errorMessage = String(localized: "Your purchase is pending approval. Pro unlocks as soon as it's approved.")
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = String(localized: "The purchase failed. Please try again.")
            return false
        }
    }

    func restore() async {
        errorMessage = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            // Cancelling the App Store sign-in also lands here; entitlements are re-read anyway.
        }
        await refreshEntitlement()
        if !hasRealSubscription {
            errorMessage = String(localized: "No active Vocabi Pro subscription was found for this Apple ID.")
        }
    }

    // MARK: Entitlement

    func refreshEntitlement() async {
        var infos: [ProEntitlement.TransactionInfo] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            infos.append(.init(productID: t.productID, expirationDate: t.expirationDate,
                               revocationDate: t.revocationDate, isUpgraded: t.isUpgraded))
        }
        let resolved = ProEntitlement.resolve(infos)
        if resolved != entitlement || resolved != ProEntitlement.load() {
            entitlement = resolved
            resolved.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Signed JWS of the current Pro transaction, used as the pack server bearer token.
    nonisolated static func currentTransactionJWS() async -> String? {
        var best: (jws: String, expires: Date)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, ProProduct(rawValue: t.productID) != nil,
                  t.revocationDate == nil else { continue }
            let expires = t.expirationDate ?? .distantFuture
            guard expires > Date() else { continue }
            if best == nil || expires > best!.expires { best = (result.jwsRepresentation, expires) }
        }
        return best?.jws
    }

    /// Bearer token value for the pack server: `dev:<token>` in debug when configured, else the JWS.
    nonisolated static func packServerToken() async -> String? {
        if let dev = DevToken.current { return "dev:\(dev)" }
        return await currentTransactionJWS()
    }
}
