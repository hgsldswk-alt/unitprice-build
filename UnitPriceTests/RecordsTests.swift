import CoreImage
import Foundation
import XCTest

final class RecordsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let locale = Locale(identifier: "en_US")

    func testHistoryBeforeSaveCurrencyAndUndo() throws {
        let old = try entry("6.39", date: now - 1, currency: "USD")
        let today = try entry("5.99", date: now, currency: "USD")
        let other = try entry("1.00", date: now - 2, currency: "EUR")
        let definition = StapleDefinition(name: "Oats", unit: .lb)
        var staple = Staple(definition: definition, entries: [old, today, other])
        XCTAssertEqual(staple.lowest(currency: "USD", before: now)?.id, old.id)
        XCTAssertEqual(staple.lowest(currency: "USD")?.id, today.id)
        XCTAssertEqual(staple.lowest(currency: "USD", excluding: today.id)?.id, old.id)
        XCTAssertEqual(staple.lowest(currency: "EUR")?.id, other.id)
        staple.entries.removeAll { $0.id == today.id }
        XCTAssertEqual(staple.lowest(currency: "USD")?.id, old.id)
    }

    func testLogIsIdempotentAndTotalsFollowEditsAndCurrency() throws {
        let baseline = try entry("2", date: now, currency: "USD").quote
        let cheap = try entry("1", date: now, currency: "USD")
        var data = LocalData(draft: .blank(currency: "USD", unit: .oz))
        let purchase = PurchaseLog(id: UUID(), date: now, day: DayKey.local(now), currency: "USD",
                                   item: cheap.item, baseline: baseline, actual: cheap.quote, display: .oz)
        XCTAssertTrue(data.log(purchase))
        XCTAssertFalse(data.log(purchase))
        var another = purchase
        another.id = UUID()
        another.currency = "EUR"
        another.day = DayKey.local(now - 86_400)
        XCTAssertTrue(data.log(another))
        XCTAssertTrue(data.purchases[0].resize(to: 50, locale: locale))
        XCTAssertEqual(data.total(currency: "USD", day: purchase.day), LocalData.milestone)
        XCTAssertEqual(data.total(currency: "EUR"), 1)
        XCTAssertEqual(data.total(currency: "EUR", day: purchase.day), 0)
        XCTAssertTrue(data.purchases[0].resize(to: 49, locale: locale))
        XCTAssertLessThan(data.total(currency: "USD"), LocalData.milestone)
        data.purchases.removeAll { $0.id == purchase.id }
        XCTAssertEqual(data.total(currency: "USD"), 0)
    }

    func testListRoundTripDedupAndLimits() throws {
        let oats = StapleDefinition(name: "  Óats  ", unit: .oz)
        let duplicate = StapleDefinition(name: "oats", unit: .g)
        let distinct = StapleDefinition(name: "oats", unit: .count)
        let encoded = try XCTUnwrap(ListCode.encode([oats, duplicate, distinct]))
        let decoded = try XCTUnwrap(ListCode.decode(" \(encoded)\n"))
        XCTAssertEqual(decoded, [oats, distinct])
        var data = LocalData(draft: .blank(currency: "USD", unit: .oz))
        let saved = try entry("4.99", date: now, currency: "USD")
        data.staples = [Staple(definition: duplicate, entries: [saved])]
        XCTAssertEqual(data.merge(decoded), 1)
        XCTAssertEqual(data.staples.first?.entries, [saved])
        XCTAssertNil(ListCode.decode("UP2:AA"))
        XCTAssertNil(ListCode.decode("UP1:AA==="))
        XCTAssertNil(ListCode.decode("UP1:AAAA"))
        XCTAssertNil(ListCode.decode(String(repeating: "A", count: ListCode.maxBytes + 1)))
        XCTAssertNil(ListCode.encode([StapleDefinition(name: "   ", unit: .g)]))
        XCTAssertNil(ListCode.encode(Array(repeating: oats, count: ListCode.maxItems + 1)))
    }

    func testReviewEarnsOnThreeDistinctDaysAndOncePerVersion() {
        var progress = ReviewProgress()
        progress.record(now)
        progress.record(now)
        progress.record(now + 86_400)
        XCTAssertFalse(progress.pending(version: "1"))
        progress.record(now + 172_800)
        XCTAssertTrue(progress.pending(version: "1"))
        progress.requestedVersions.insert("1")
        XCTAssertFalse(progress.pending(version: "1"))
        XCTAssertTrue(progress.pending(version: "2"))
    }

    func testQRSupportsPlaceholderAndActualStoreID() throws {
        XCTAssertEqual(DownloadQR.target(appStoreID: ""), DownloadQR.placeholder)
        for id in [nil, "1234567890"] as [String?] {
            let target = DownloadQR.target(appStoreID: id)
            let pixels = try XCTUnwrap(DownloadQR.image(for: target))
            let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                   options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
            let features = detector.features(in: CIImage(cgImage: pixels))
            XCTAssertEqual(features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first, target)
        }
    }

    func testLocalDataCodableRoundTrip() throws {
        var local = LocalData(draft: .blank(currency: "USD", unit: .oz))
        local.draft.items[0].price = "4.49"
        let price = try entry("4.49", date: now, currency: "USD")
        local.staples = [Staple(definition: .init(name: "Oats", unit: .oz), entries: [price])]
        local.pinned = local.staples.first?.id
        let decoded = try JSONDecoder().decode(LocalData.self, from: JSONEncoder().encode(local))
        XCTAssertEqual(decoded, local)
    }

    private func entry(_ price: String, date: Date, currency: String) throws -> PriceEntry {
        let item = ShelfItem(letter: 0, price: price, size: "32", unit: .oz)
        return try PriceEntry(date: date, currency: currency, item: item,
                              quote: XCTUnwrap(item.quote(locale: locale)), display: .oz)
    }
}
