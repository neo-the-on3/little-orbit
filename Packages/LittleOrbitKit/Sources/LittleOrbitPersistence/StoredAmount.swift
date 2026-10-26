import Foundation
import LittleOrbitDomain

/// The one rule for how an amount is stored (`MinorUnitDecimal.Stored`). The record mapping and the write checks
/// (`LedgerWriteValidation`) both call `stored(_:currencyCode:)` itself, so a write that would fail while records
/// are changed fails before any is (#265).
enum StoredAmount {
    /// At the currency's decimal places. With no currency (a scheduled item whose account was just deleted,
    /// D288.1), at the value's own decimal places, at least the fallback currency's, so nothing is rounded.
    static func stored(_ value: Decimal, currencyCode: String?) throws -> MinorUnitDecimal.Stored {
        guard let currencyCode else {
            let fallback = CurrencyCode.minorUnits(for: CurrencyCode.fallback) ?? 0
            return try MinorUnitDecimal.store(
                value,
                scale: max(fallback, MinorUnitDecimal.fractionalDigits(in: value)),
            )
        }
        return try MinorUnitDecimal.store(value, scale: CurrencyCode.minorUnits(for: currencyCode) ?? 0)
    }
}
