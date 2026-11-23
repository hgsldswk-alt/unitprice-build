import Foundation

final class LocalizationBundle: NSObject {}

enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: LocalizationBundle.self), comment: "")
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: .current, arguments: args)
    }

    static func number(_ value: Decimal, digits: Int = 2, minimum: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimum
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    static func money(_ value: Decimal, code: String, precision: Int? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        if let precision {
            formatter.minimumFractionDigits = precision
            formatter.maximumFractionDigits = precision
        }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    static func currencyDigits(_ code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }
}
