import Foundation

enum Dimension: String, Codable, CaseIterable, Sendable {
    case weight, volume, count, sheets, rolls, layers
}

enum ShelfUnit: String, Codable, CaseIterable, Sendable {
    case oz, lb, g, kg, ml, l, floz, count, sheets, rolls, layers

    var label: String { L.t("unit." + rawValue) }

    var dimension: Dimension {
        switch self {
        case .oz, .lb, .g, .kg: .weight
        case .ml, .l, .floz: .volume
        case .count: .count
        case .sheets: .sheets
        case .rolls: .rolls
        case .layers: .layers
        }
    }

    var factor: Decimal {
        switch self {
        case .oz: Decimal(string: "28.349523125")!
        case .lb: Decimal(string: "453.59237")!
        case .kg, .l: 1_000
        case .floz: Decimal(string: "29.5735295625")!
        default: 1
        }
    }
}

enum DisplayUnit: String, Codable, CaseIterable, Sendable {
    case oz, lb, g100, kg, ml100, l, floz, count, sheets, rolls, layers100

    var unit: ShelfUnit {
        switch self {
        case .g100: .g
        case .ml100: .ml
        case .layers100: .layers
        default: ShelfUnit(rawValue: rawValue)!
        }
    }

    var factor: Decimal {
        unit.factor * ([.g100, .ml100, .layers100].contains(self) ? 100 : 1)
    }

    var label: String {
        [.g100, .ml100, .layers100].contains(self) ? L.f("unit.hundred", unit.label) : unit.label
    }

    static func standard(for unit: ShelfUnit, imperial: Bool) -> Self {
        switch unit.dimension {
        case .weight: imperial ? .oz : .g100
        case .volume: imperial ? .floz : .ml100
        case .count: .count
        case .sheets: .sheets
        case .rolls: .rolls
        case .layers: .layers100
        }
    }
}

enum OfferKind: String, Codable, CaseIterable, Sendable {
    case regular, bundle, perPack, freePacks
    var label: String { L.t("offer." + rawValue) }
}

struct Offer: Codable, Equatable, Sendable {
    var kind: OfferKind = .regular
    var total: Decimal = 0
    var paid = 2
    var free = 1

    func cost(packs: Int, shelf: Decimal?) -> Decimal? {
        guard (1...9999).contains(packs), (1...9999).contains(paid),
              total >= 0, let _ = MoneyInput.bounded(total) else { return nil }
        let ordinary = shelf.flatMap { $0 >= 0 ? MoneyInput.bounded($0) : nil }
        switch kind {
        case .regular:
            return ordinary.map { $0 * Decimal(packs) }
        case .perPack:
            return total * Decimal(packs) / Decimal(paid)
        case .bundle:
            let remainder = packs % paid
            guard remainder == 0 || ordinary != nil else { return nil }
            return total * Decimal(packs / paid) + (ordinary ?? 0) * Decimal(remainder)
        case .freePacks:
            guard (1...9999).contains(free), let ordinary else { return nil }
            return ordinary * Decimal(packs - (packs / (paid + free)) * free)
        }
    }
}

enum MoneyInput {
    static func bounded(_ value: Decimal) -> Decimal? {
        guard !value.isNaN, abs(value) <= 999_999_999 else { return nil }
        return value
    }

    static func parse(_ text: String, locale: Locale) -> Decimal? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.utf8.count <= 64 else { return nil }
        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let groupPattern = NSRegularExpression.escapedPattern(for: grouping)
        let grouped = !grouping.isEmpty && grouping != separator &&
            raw.range(of: "^-?[0-9]{1,3}(?:\(groupPattern)[0-9]{3})+(?:\(NSRegularExpression.escapedPattern(for: separator))[0-9]+)?$",
                      options: .regularExpression) != nil
        let clean = grouped ? raw.replacingOccurrences(of: grouping, with: "") : raw
        let normalized = clean.replacingOccurrences(of: separator, with: ".")
        guard (separator == "." || !clean.contains(".") || !clean.contains(separator)),
              normalized.range(of: "^-?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)$", options: .regularExpression) != nil,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return bounded(value)
    }

    static func priceFinished(_ text: String, currency: String, locale: Locale) -> Bool {
        let digits = L.currencyDigits(currency)
        guard digits > 0, let value = parse(text, locale: locale), value >= 0 else { return false }
        let separator = locale.decimalSeparator ?? "."
        let split = text.components(separatedBy: text.contains(separator) ? separator : ".")
        return split.count == 2 && split[1].count == digits
    }
}

struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var letter: Int
    var price = ""
    var size = ""
    var unit: ShelfUnit
    var packs = 1
    var offer = Offer()
    var paperPly: Int?
    var sheetsPerRoll = ""

    var name: String { L.f("item.name", String(UnicodeScalar(65 + min(9, max(0, letter)))!)) }
    var isEmpty: Bool { price.isEmpty && size.isEmpty && sheetsPerRoll.isEmpty && offer.kind == .regular }

    func quote(locale: Locale, packs override: Int? = nil) -> Quote? {
        guard let size = MoneyInput.parse(size, locale: locale), size > 0 else { return nil }
        let packs = override ?? packs
        let shelf = MoneyInput.parse(price, locale: locale)
        guard price.isEmpty || (shelf.map { $0 >= 0 } ?? false),
              let cost = offer.cost(packs: packs, shelf: shelf) else { return nil }

        var quantity = size * unit.factor
        if let paperPly, unit == .sheets || unit == .layers {
            guard (1...9).contains(paperPly),
                  let sheets = MoneyInput.parse(sheetsPerRoll, locale: locale), sheets > 0 else { return nil }
            quantity *= sheets
            if unit == .layers { quantity *= Decimal(paperPly) }
        }
        return Quote(id: id, unit: unit, cost: cost, quantity: quantity * Decimal(packs), packs: packs)
    }
}

struct Quote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var unit: ShelfUnit
    var cost: Decimal
    var quantity: Decimal
    var packs: Int
    var rate: Decimal { cost / quantity }
}

struct Comparison {
    let ranked: [Quote]
    let mismatch: Bool

    init(_ quotes: [Quote]) {
        mismatch = Set(quotes.map { $0.unit.dimension }).count > 1
        ranked = mismatch ? [] : quotes.sorted { $0.rate < $1.rate }
    }

    var ready: Bool { ranked.count >= 2 }
    var lowest: Quote? { ready ? ranked.first : nil }

    func isWinner(_ quote: Quote) -> Bool {
        guard let lowest else { return false }
        return quote.cost * lowest.quantity == lowest.cost * quote.quantity
    }

    var tie: Bool { ranked.prefix(2).filter(isWinner).count == 2 }

    var alternatives: [Quote] { ready ? ranked.filter { !isWinner($0) } : [] }

    func alternative(preferredID: UUID?) -> Quote? {
        let alternatives = self.alternatives
        return alternatives.first { $0.id == preferredID } ?? alternatives.first
    }

    func higherPercent(_ quote: Quote) -> Decimal? {
        guard let lowest, lowest.cost > 0 else { return nil }
        return max(0, (quote.cost * lowest.quantity / (lowest.cost * quote.quantity) - 1) * 100)
    }

    static func lowerPercent(chosen: Quote, alternative: Quote) -> Decimal? {
        guard chosen.unit.dimension == alternative.unit.dimension, alternative.cost > 0 else { return nil }
        return max(0, (1 - chosen.cost * alternative.quantity / (alternative.cost * chosen.quantity)) * 100)
    }

    static func savings(chosen: Quote, alternative: Quote) -> Decimal {
        guard chosen.unit.dimension == alternative.unit.dimension else { return 0 }
        let difference = (alternative.cost * chosen.quantity - chosen.cost * alternative.quantity) / alternative.quantity
        var value = max(0, difference)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }
}

struct ComparisonDraft: Codable, Equatable, Sendable {
    var id = UUID()
    var items: [ShelfItem]
    var currency: String
    var display: DisplayUnit?
    var lastUnit: ShelfUnit?
    var secondUnitPinned: Bool?

    static func blank(currency: String, unit: ShelfUnit) -> Self {
        Self(items: [ShelfItem(letter: 0, unit: unit), ShelfItem(letter: 1, unit: unit)], currency: currency)
    }

    var imperial: Bool { currency == "USD" }

    mutating func setUnit(_ unit: ShelfUnit, for id: UUID, ply: Int?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let first = items.firstIndex(where: { $0.letter == 0 })
        let second = items.firstIndex(where: { $0.letter == 1 })
        if secondUnitPinned == nil, let first, let second {
            secondUnitPinned = items[first].unit != items[second].unit || items[first].paperPly != items[second].paperPly
        }
        items[index].setUnit(unit, ply: ply)
        if index == second { secondUnitPinned = true }
        if index == first, let second, secondUnitPinned != true {
            items[second].setUnit(unit, ply: ply)
        }
        lastUnit = unit == .layers && ply != nil ? .rolls : unit
    }
}

private extension ShelfItem {
    mutating func setUnit(_ unit: ShelfUnit, ply: Int?) {
        self.unit = unit
        paperPly = ply
        if ply == nil { sheetsPerRoll = "" }
    }
}
