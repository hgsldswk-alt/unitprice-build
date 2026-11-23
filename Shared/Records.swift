import Foundation

struct StapleDefinition: Codable, Equatable, Sendable {
    var name: String
    var unit: ShelfUnit

    var key: String {
        let words = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                             locale: Locale(identifier: "en_US_POSIX")) + "|" + unit.dimension.rawValue
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        name.count <= 80 && name.utf8.count <= 320 &&
        !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

struct PriceEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var currency: String
    var item: ShelfItem
    var quote: Quote
    var display: DisplayUnit
}

struct Staple: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var definition: StapleDefinition
    var entries: [PriceEntry] = []

    func lowest(currency: String, before: Date = .distantFuture, excluding: UUID? = nil) -> PriceEntry? {
        entries.filter {
            $0.currency == currency && $0.date < before && $0.id != excluding &&
            $0.quote.unit.dimension == definition.unit.dimension
        }
        .min {
            if $0.quote.rate == $1.quote.rate { return $0.date < $1.date }
            return $0.quote.rate < $1.quote.rate
        }
    }
}

struct PurchaseLog: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var day: String
    var currency: String
    var item: ShelfItem
    var baseline: Quote
    var actual: Quote
    var display: DisplayUnit

    var saved: Decimal { Comparison.savings(chosen: actual, alternative: baseline) }

    mutating func resize(to count: Int, locale: Locale) -> Bool {
        guard let revised = item.quote(locale: locale, packs: count) else { return false }
        actual = revised
        return true
    }
}

enum DayKey {
    static func local(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func utc(_ date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 86_400))
    }
}

struct ReviewProgress: Codable, Equatable, Sendable {
    var localDays: Set<String> = []
    var utcDays: Set<Int> = []
    var requestedVersions: Set<String> = []

    mutating func record(_ date: Date) {
        guard localDays.count < 3 else { return }
        let local = DayKey.local(date)
        let utc = DayKey.utc(date)
        guard !localDays.contains(local), !utcDays.contains(utc) else { return }
        localDays.insert(local)
        utcDays.insert(utc)
    }

    func pending(version: String) -> Bool {
        localDays.count >= 3 && !requestedVersions.contains(version)
    }
}

struct LocalData: Codable, Equatable, Sendable {
    var version = 1
    var draft: ComparisonDraft
    var staples: [Staple] = []
    var purchases: [PurchaseLog] = []
    var pinned: UUID?
    var milestonesSeen: Set<String> = []
    var review = ReviewProgress()

    @discardableResult
    mutating func merge(_ definitions: [StapleDefinition]) -> Int {
        var keys = Set(staples.map { $0.definition.key })
        var added = 0
        for definition in definitions where keys.insert(definition.key).inserted {
            staples.append(Staple(definition: definition))
            added += 1
        }
        return added
    }

    @discardableResult
    mutating func log(_ purchase: PurchaseLog) -> Bool {
        guard !purchases.contains(where: { $0.id == purchase.id }) else { return false }
        purchases.append(purchase)
        return true
    }

    func total(currency: String, day: String? = nil) -> Decimal {
        purchases.lazy.filter { $0.currency == currency && (day == nil || $0.day == day) }
            .reduce(0) { $0 + $1.saved }
    }

    static let milestone: Decimal = 50
}

enum ListCode {
    private struct Payload: Codable {
        let v: Int
        let items: [StapleDefinition]
    }

    static let maxItems = 200
    static let maxBytes = 128_000
    static let fileExtension = "unitpricelist"

    static func encode(_ items: [StapleDefinition]) -> String? {
        guard items.count <= maxItems, items.allSatisfy(\.isValid),
              let data = try? JSONEncoder().encode(Payload(v: 1, items: items)) else { return nil }
        let code = "UP1:" + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return code.utf8.count <= maxBytes ? code : nil
    }

    static func decode(_ input: String) -> [StapleDefinition]? {
        guard input.utf8.count <= maxBytes else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("UP1:") else { return nil }
        let body = String(trimmed.dropFirst(4))
        guard !body.isEmpty, body.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        var base64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.v == 1, payload.items.count <= maxItems, payload.items.allSatisfy(\.isValid) else { return nil }
        var keys = Set<String>()
        return payload.items.filter { keys.insert($0.key).inserted }
    }
}
