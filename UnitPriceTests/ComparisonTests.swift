import Foundation
import XCTest

final class ComparisonTests: XCTestCase {
    let english = Locale(identifier: "en_US")
    let german = Locale(identifier: "de_DE")

    func testWeightAndVolumePairsNormalizeToSameQuantity() throws {
        let pound = try XCTUnwrap(item("2", "2", .lb).quote(locale: english))
        let ounces = try XCTUnwrap(item("2", "32", .oz).quote(locale: english))
        let grams = try XCTUnwrap(item("2", "907.18474", .g).quote(locale: english))
        let kilograms = try XCTUnwrap(item("2", "0.90718474", .kg).quote(locale: english))
        XCTAssertTrue([ounces, grams, kilograms].allSatisfy { $0.quantity == pound.quantity })
        XCTAssertTrue(Comparison([ounces, kilograms]).tie)

        let liters = try XCTUnwrap(item("2", "1", .l).quote(locale: english))
        let ml = try XCTUnwrap(item("2", "1000", .ml).quote(locale: english))
        let fluidOunce = try XCTUnwrap(item("2", "1", .floz).quote(locale: english))
        XCTAssertEqual(liters.quantity, ml.quantity)
        XCTAssertEqual(fluidOunce.quantity, Decimal(string: "29.5735295625"))
        XCTAssertTrue(Comparison([liters, ounces]).mismatch)
    }

    func testPaperRollsSheetsAndLayers() throws {
        var paper = item("12", "12", .layers)
        paper.paperPly = 2
        paper.sheetsPerRoll = "200"
        let layers = try XCTUnwrap(paper.quote(locale: english))
        XCTAssertEqual(layers.quantity, 4800)
        XCTAssertEqual(layers.rate * DisplayUnit.layers100.factor, Decimal(string: "0.25"))

        paper.unit = .sheets
        let sheets = try XCTUnwrap(paper.quote(locale: english))
        XCTAssertEqual(sheets.quantity, 2400)
        paper.unit = .rolls
        XCTAssertEqual(paper.quote(locale: english)?.quantity, 12)
        XCTAssertTrue(Comparison([layers, sheets]).mismatch)
        paper.unit = .layers
        paper.paperPly = 0
        XCTAssertNil(paper.quote(locale: english))
    }

    func testInvalidFreeTiesAndNearRates() throws {
        XCTAssertNil(item("", "18", .oz).quote(locale: english))
        XCTAssertNil(item("-1", "18", .oz).quote(locale: english))
        XCTAssertNil(item("1", "0", .oz).quote(locale: english))
        XCTAssertNil(item("1", "-1", .oz).quote(locale: english))
        let free = try XCTUnwrap(item("0", "1", .count).quote(locale: english))
        let paid = try XCTUnwrap(item("1", "1", .count).quote(locale: english))
        let nearer = try XCTUnwrap(item("1.0001", "1", .count).quote(locale: english))
        XCTAssertFalse(Comparison([paid]).ready)
        XCTAssertTrue(Comparison([free, paid]).isWinner(free))
        XCTAssertNil(Comparison([free, paid]).higherPercent(paid))
        XCTAssertEqual(Comparison([paid, nearer]).higherPercent(nearer), Decimal(string: "0.01"))
        XCTAssertFalse(Comparison([paid, nearer]).tie)
        XCTAssertTrue(Comparison([paid, try XCTUnwrap(item("2", "2", .count).quote(locale: english))]).tie)
    }

    func testLocaleAndCompleteInput() {
        XCTAssertEqual(MoneyInput.parse("1,234.56", locale: english), Decimal(string: "1234.56"))
        XCTAssertEqual(MoneyInput.parse("1.234,56", locale: german), Decimal(string: "1234.56"))
        XCTAssertEqual(MoneyInput.parse(" 1,5 ", locale: german), Decimal(string: "1.5"))
        XCTAssertEqual(MoneyInput.parse(".5", locale: english), Decimal(string: "0.5"))
        XCTAssertNil(MoneyInput.parse("1,2.3", locale: english))
        XCTAssertNil(MoneyInput.parse("1e3", locale: english))
        XCTAssertNil(MoneyInput.parse("12.00p", locale: english))
        XCTAssertTrue(MoneyInput.priceFinished("12.00", currency: "USD", locale: english))
        XCTAssertTrue(MoneyInput.priceFinished("12,00", currency: "USD", locale: german))
        XCTAssertFalse(MoneyInput.priceFinished("12", currency: "USD", locale: english))
        XCTAssertFalse(MoneyInput.priceFinished("12.0", currency: "USD", locale: english))
    }

    func testPackagesAndOfferThresholds() throws {
        var pack = item("3.79", "12", .oz)
        pack.packs = 4
        XCTAssertEqual(pack.quote(locale: english)?.cost, Decimal(string: "15.16"))
        XCTAssertEqual(pack.quote(locale: english)?.quantity, 48 * ShelfUnit.oz.factor)

        let shelf = Decimal(string: "3.79")
        let bundle = Offer(kind: .bundle, total: 5, paid: 2)
        XCTAssertEqual(bundle.cost(packs: 1, shelf: shelf), shelf)
        XCTAssertEqual(bundle.cost(packs: 2, shelf: nil), 5)
        XCTAssertEqual(bundle.cost(packs: 3, shelf: shelf), Decimal(string: "8.79"))
        XCTAssertNil(bundle.cost(packs: 3, shelf: nil))
        XCTAssertNil(bundle.cost(packs: 1, shelf: nil))
        XCTAssertEqual(Offer(kind: .perPack, total: 5, paid: 2).cost(packs: 1, shelf: nil), Decimal(string: "2.50"))

        pack.offer = Offer(kind: .freePacks, paid: 2, free: 1)
        XCTAssertEqual(pack.quote(locale: english, packs: 3)?.cost, Decimal(string: "7.58"))
        XCTAssertEqual(pack.quote(locale: english, packs: 7)?.cost, Decimal(string: "18.95"))
        XCTAssertNil(pack.quote(locale: english, packs: 0))
    }

    func testQuotedSavingsMatchDesign() throws {
        let loser = try XCTUnwrap(item("4.49", "18", .oz).quote(locale: english))
        let winner = try XCTUnwrap(item("5.99", "32", .oz).quote(locale: english))
        let comparison = Comparison([loser, winner])
        XCTAssertEqual(comparison.lowest, winner)
        XCTAssertEqual(Comparison.savings(chosen: winner, alternative: loser), Decimal(string: "1.99"))
        let higher = try XCTUnwrap(comparison.higherPercent(loser))
        XCTAssertEqual(NSDecimalNumber(decimal: higher).doubleValue, 33.259, accuracy: 0.01)
        let lower = try XCTUnwrap(Comparison.lowerPercent(chosen: winner, alternative: loser))
        XCTAssertEqual(NSDecimalNumber(decimal: lower).doubleValue, 24.958, accuracy: 0.01)
    }

    func testAltSelectionFallsBackToNextRankedPrice() throws {
        let first = try XCTUnwrap(item("1", "1", .count).quote(locale: english))
        let second = try XCTUnwrap(item("2", "1", .count).quote(locale: english))
        let third = try XCTUnwrap(item("3", "1", .count).quote(locale: english))
        let comparison = Comparison([third, first, second])
        XCTAssertEqual(comparison.alternative(preferredID: third.id), third)
        XCTAssertEqual(comparison.alternative(preferredID: first.id), second)
        XCTAssertEqual(Comparison.savings(chosen: first, alternative: third), 2)
    }

    func testSecondUnitFollowsFirstUntilExplicitlyChosenAndRespectsOldDrafts() throws {
        var draft = ComparisonDraft.blank(currency: "USD", unit: .oz)
        let first = draft.items[0].id
        let second = draft.items[1].id
        draft.setUnit(.lb, for: first, ply: nil)
        XCTAssertEqual(draft.items[1].unit, .lb)
        draft.setUnit(.lb, for: second, ply: nil)
        draft = try JSONDecoder().decode(ComparisonDraft.self, from: JSONEncoder().encode(draft))
        draft.setUnit(.g, for: first, ply: nil)
        XCTAssertEqual(draft.items[1].unit, .lb)

        var beforeFlag = ComparisonDraft.blank(currency: "USD", unit: .oz)
        beforeFlag.items[1].unit = .ml
        var restored = try JSONDecoder().decode(ComparisonDraft.self, from: JSONEncoder().encode(beforeFlag))
        let originalFirst = restored.items[0].id
        restored.setUnit(.kg, for: originalFirst, ply: nil)
        XCTAssertEqual(restored.items[1].unit, .ml)
    }

    private func item(_ price: String, _ size: String, _ unit: ShelfUnit) -> ShelfItem {
        ShelfItem(letter: 0, price: price, size: size, unit: unit)
    }
}
