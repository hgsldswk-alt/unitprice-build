import Foundation
import XCTest

final class EntitlementTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testPaidBuildHasThirtyDaysFromFirstOpenAndNeverRestartsOnClockRollback() {
        XCTAssertFalse(Launch.freePeriod)
        var entitlement = Entitlement(firstOpen: now)
        let end = now + 30 * 86_400
        XCTAssertEqual(entitlement.trialEnd, end)
        XCTAssertTrue(entitlement.hasPro(at: end - 1))
        XCTAssertFalse(entitlement.hasPro(at: end))
        entitlement.observe(end)
        XCTAssertFalse(entitlement.hasPro(at: now))
        XCTAssertEqual(entitlement.daysLeft(at: now), 0)
    }

    func testProStartForFormerFreeBuildAndReceiptCannotExtend() {
        var entitlement = Entitlement(firstOpen: now - 90 * 86_400, proStartedAt: now)
        XCTAssertEqual(entitlement.trialStart, now)
        entitlement.applyTrialReceipt(now + 7 * 86_400)
        XCTAssertEqual(entitlement.trialStart, now)
        entitlement.applyTrialReceipt(now - 4 * 86_400)
        XCTAssertEqual(entitlement.trialStart, now - 4 * 86_400)
        XCTAssertEqual(entitlement.daysLeft(at: now), 26)
    }

    func testRestoredPurchasePersistsOfflineAndRevocationReturnsToFree() throws {
        var entitlement = Entitlement(firstOpen: now - 31 * 86_400)
        XCTAssertFalse(entitlement.hasPro(at: now))
        entitlement.purchasedPro = true
        let data = try JSONEncoder().encode(entitlement)
        entitlement = try JSONDecoder().decode(Entitlement.self, from: data)
        XCTAssertTrue(entitlement.hasPro(at: now))
        entitlement.purchasedPro = false
        XCTAssertFalse(entitlement.hasPro(at: now))
        XCTAssertTrue(entitlement.hasPro(at: now, free: true))
    }

    func testWidgetHidesLowAtExpiry() {
        let entitlement = Entitlement(firstOpen: now)
        let item = ShelfItem(letter: 0, unit: .oz)
        let quote = Quote(id: item.id, unit: .oz, cost: 3, quantity: 30, packs: 1)
        let entry = PriceEntry(date: now, currency: "USD", item: item, quote: quote, display: .oz)
        let snapshot = WidgetSnapshot(entitlement: entitlement, name: "Oats", staple: UUID(), low: entry)
        XCTAssertEqual(snapshot.visibleLow(at: entitlement.trialEnd - 1), entry)
        XCTAssertNil(snapshot.visibleLow(at: entitlement.trialEnd))
    }
}
