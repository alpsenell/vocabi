import XCTest
@testable import VocabCore

final class ProEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "test.pro.\(UUID().uuidString)"))
    }

    func testPersistenceRoundTripUnderContractKey() throws {
        let d = try defaults()
        XCTAssertEqual(ProEntitlement.load(from: d), .inactive)
        let e = ProEntitlement(isActive: true, productID: ProProduct.monthly.rawValue, expiresAt: now)
        e.save(to: d)
        XCTAssertNotNil(d.data(forKey: "pro.entitlement.v1"))
        XCTAssertEqual(ProEntitlement.load(from: d), e)
        XCTAssertEqual(ProEntitlement.load(from: d).product, .monthly)
        ProEntitlement.inactive.save(to: d)
        XCTAssertFalse(ProEntitlement.load(from: d).isActive)
    }

    func testStoredJSONIsReadableByWidgetSchema() throws {
        let d = try defaults()
        ProEntitlement(isActive: true, productID: "p", expiresAt: now).save(to: d)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(d.data(forKey: ProEntitlement.defaultsKey))) as? [String: Any])
        XCTAssertEqual(obj["isActive"] as? Bool, true)
        XCTAssertEqual(obj["productID"] as? String, "p")
        XCTAssertNotNil(obj["expiresAt"] as? String) // ISO-8601
    }

    func testCorruptDataLoadsInactive() throws {
        let d = try defaults()
        d.set(Data("garbage".utf8), forKey: ProEntitlement.defaultsKey)
        XCTAssertEqual(ProEntitlement.load(from: d), .inactive)
    }

    func testIsActiveAtHonorsExpiry() {
        let e = ProEntitlement(isActive: true, productID: "p", expiresAt: now)
        XCTAssertTrue(e.isActive(at: now.addingTimeInterval(-1)))
        XCTAssertFalse(e.isActive(at: now.addingTimeInterval(1)))
        XCTAssertTrue(ProEntitlement(isActive: true).isActive(at: .distantFuture))
        XCTAssertFalse(ProEntitlement.inactive.isActive(at: now))
    }

    func testResolvePicksLatestValidProTransaction() {
        typealias T = ProEntitlement.TransactionInfo
        let weekly = ProProduct.weekly.rawValue, monthly = ProProduct.monthly.rawValue
        let txs = [
            T(productID: weekly, expirationDate: now.addingTimeInterval(86_400)),
            T(productID: monthly, expirationDate: now.addingTimeInterval(20 * 86_400)),
            T(productID: monthly, expirationDate: now.addingTimeInterval(40 * 86_400), revocationDate: now),
            T(productID: "com.other.product", expirationDate: now.addingTimeInterval(99 * 86_400)),
        ]
        let e = ProEntitlement.resolve(txs, now: now)
        XCTAssertTrue(e.isActive)
        XCTAssertEqual(e.productID, monthly)
        XCTAssertEqual(e.expiresAt, now.addingTimeInterval(20 * 86_400))
    }

    func testResolveInactiveCases() {
        typealias T = ProEntitlement.TransactionInfo
        XCTAssertEqual(ProEntitlement.resolve([], now: now), .inactive)
        XCTAssertEqual(ProEntitlement.resolve([T(productID: ProProduct.weekly.rawValue, expirationDate: now.addingTimeInterval(-1))], now: now), .inactive)
        XCTAssertEqual(ProEntitlement.resolve([T(productID: ProProduct.weekly.rawValue, expirationDate: nil, isUpgraded: true)], now: now), .inactive)
    }

    func testSavingsPercentFromPrices() {
        XCTAssertEqual(ProPricing.monthlySavingsPercent(weekly: ProProduct.weekly.fallbackPrice,
                                                        monthly: ProProduct.monthly.fallbackPrice), 16)
        XCTAssertEqual(ProPricing.monthlySavingsPercent(weekly: 1, monthly: 4), 0)
        XCTAssertEqual(ProPricing.monthlySavingsPercent(weekly: 0, monthly: 4), 0)
        XCTAssertEqual(ProPricing.monthlySavingsPercent(weekly: Decimal(string: "79.99")!, monthly: Decimal(string: "249.99")!), 21)
    }

    func testProductIDsMatchPricingDoc() {
        XCTAssertEqual(ProProduct.allIDs, ["com.alpsenel.wordwidget.pro.weekly", "com.alpsenel.wordwidget.pro.monthly"])
    }
}
