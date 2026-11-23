import Foundation

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let key = "unitprice.widget.v1"
    var entitlement: Entitlement
    var name: String?
    var staple: UUID?
    var low: PriceEntry?

    func visibleLow(at date: Date) -> PriceEntry? {
        entitlement.hasPro(at: date) ? low : nil
    }
}
