import Foundation

/// Vocabi Pro product identifiers (docs/PRICING.md). Shared by app, widget and tests.
public enum ProProduct: String, CaseIterable, Codable, Sendable {
    case weekly = "com.alpsenel.wordwidget.pro.weekly"
    case monthly = "com.alpsenel.wordwidget.pro.monthly"

    public static let subscriptionGroupName = "Vocabi Pro"
    public static var allIDs: [String] { allCases.map(\.rawValue) }

    /// US prices used when the App Store products can't be loaded (display only).
    public var fallbackPrice: Decimal {
        switch self {
        case .weekly: return Decimal(string: "2.99")!
        case .monthly: return Decimal(string: "9.99")!
        }
    }

    public var fallbackDisplayPrice: String {
        switch self {
        case .weekly: return "$2.99"
        case .monthly: return "$9.99"
        }
    }
}

public enum ProPricing {
    /// Percentage saved by monthly vs. four weeks of weekly, rounded down (9.99 vs 11.96 → 16).
    /// Returns 0 when monthly is not cheaper.
    public static func monthlySavingsPercent(weekly: Decimal, monthly: Decimal) -> Int {
        let fourWeeks = weekly * 4
        guard fourWeeks > 0, monthly < fourWeeks else { return 0 }
        let ratio = NSDecimalNumber(decimal: (fourWeeks - monthly) / fourWeeks * 100).doubleValue
        return Int(ratio.rounded(.down))
    }
}

/// Snapshot of the user's Pro status, written by the app (StoreKit) to the App Group so the widget
/// can read it without touching StoreKit.
public struct ProEntitlement: Codable, Equatable, Sendable {
    public static let defaultsKey = "pro.entitlement.v1"

    public var isActive: Bool
    public var productID: String?
    public var expiresAt: Date?

    public init(isActive: Bool, productID: String? = nil, expiresAt: Date? = nil) {
        self.isActive = isActive
        self.productID = productID
        self.expiresAt = expiresAt
    }

    public static let inactive = ProEntitlement(isActive: false)

    public var product: ProProduct? { productID.flatMap(ProProduct.init(rawValue:)) }

    /// `isActive`, but also false once `expiresAt` has passed (the widget may read a snapshot the
    /// app hasn't refreshed since the subscription lapsed).
    public func isActive(at date: Date) -> Bool {
        guard isActive else { return false }
        if let expiresAt { return expiresAt > date }
        return true
    }

    // MARK: Persistence

    public static var sharedDefaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard }

    public static func load(from defaults: UserDefaults = sharedDefaults) -> ProEntitlement {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder.iso8601.decode(ProEntitlement.self, from: data) else { return .inactive }
        return value
    }

    public func save(to defaults: UserDefaults = sharedDefaults) {
        if let data = try? JSONEncoder.iso8601.encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    // MARK: Resolution from StoreKit transactions (pure, testable)

    /// The fields of a StoreKit `Transaction` that matter for entitlement.
    public struct TransactionInfo: Equatable, Sendable {
        public var productID: String
        public var expirationDate: Date?
        public var revocationDate: Date?
        public var isUpgraded: Bool

        public init(productID: String, expirationDate: Date?, revocationDate: Date? = nil, isUpgraded: Bool = false) {
            self.productID = productID
            self.expirationDate = expirationDate
            self.revocationDate = revocationDate
            self.isUpgraded = isUpgraded
        }
    }

    /// Picks the active Pro transaction with the latest expiry from verified current entitlements.
    public static func resolve(_ transactions: [TransactionInfo], now: Date = Date()) -> ProEntitlement {
        let valid = transactions.filter { t in
            ProProduct(rawValue: t.productID) != nil
                && t.revocationDate == nil
                && !t.isUpgraded
                && (t.expirationDate.map { $0 > now } ?? true)
        }
        guard let best = valid.max(by: { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) })
        else { return .inactive }
        return ProEntitlement(isActive: true, productID: best.productID, expiresAt: best.expirationDate)
    }
}

extension JSONEncoder {
    static var iso8601: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
