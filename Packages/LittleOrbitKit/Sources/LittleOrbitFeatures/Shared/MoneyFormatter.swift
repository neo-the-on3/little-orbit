import Foundation
import LittleOrbitDomain

/// Formats money in the device's locale (D8): ₹ lakh grouping in India, 1.234,56 € in Germany, and the
/// currency's own decimal places (JPY 0, KWD 3).
///
/// Negative amounts use a real minus sign (U+2212) before the symbol, as in the designs: −₹30,000.00.
public struct MoneyFormatter: Sendable {
    public var locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public func string(_ amount: Decimal, currencyCode: String, showsPlus: Bool = false) -> String {
        let magnitude = amount.magnitude.formatted(.currency(code: currencyCode).locale(locale))
        if amount < 0 {
            return "\u{2212}" + magnitude
        }
        if amount > 0 && showsPlus {
            return "+" + magnitude
        }
        return magnitude
    }

    /// An amount as the form shows it for editing: grouped, with the currency's decimals and no symbol.
    public func inputString(_ amount: Decimal, currencyCode: String) -> String {
        let digits = CurrencyCode.minorUnits(for: currencyCode) ?? 2
        return amount.magnitude.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// The sample used in "Enter an amount like 1,25,000.00."
    public func exampleAmount(currencyCode: String) -> String {
        inputString(125_000, currencyCode: currencyCode)
    }
}

/// How an amount is coloured. Maps to the `money/*` tokens in the views.
public enum AmountTone: Sendable, Equatable {
    case neutral
    case positive
    case negative
}

/// Count badges are hidden at 0 and cap at "99+" (D104).
public enum CountBadge {
    public static func text(for count: Int) -> String? {
        if count <= 0 {
            return nil
        }
        return count > 99 ? "99+" : String(count)
    }
}
