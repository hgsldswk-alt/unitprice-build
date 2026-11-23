import Foundation

struct Entitlement: Codable, Equatable, Sendable {
    var firstOpen: Date
    var proStartedAt: Date?
    var trialReceiptAt: Date?
    var highWater: Date?
    var purchasedPro = false

    static let trialLength: TimeInterval = 30 * 86_400

    var trialStart: Date {
        let localStart = proStartedAt ?? firstOpen
        return min(trialReceiptAt ?? localStart, localStart)
    }

    var trialEnd: Date { trialStart.addingTimeInterval(Self.trialLength) }

    func effectiveDate(_ now: Date) -> Date { max(now, highWater ?? now) }

    mutating func observe(_ now: Date) { highWater = effectiveDate(now) }

    mutating func applyTrialReceipt(_ originalDate: Date) {
        trialReceiptAt = min(originalDate, trialReceiptAt ?? originalDate)
    }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        free || purchasedPro || effectiveDate(now) < trialEnd
    }

    func daysLeft(at now: Date) -> Int {
        max(0, Int(ceil(trialEnd.timeIntervalSince(effectiveDate(now)) / 86_400)))
    }
}
