import Foundation

public enum AmountInputError: Error, Equatable, Sendable {
    /// Letters, more than one decimal separator, or no digits at all.
    case notANumber
    /// A minus sign or brackets. The sign comes from the account type and toggle instead (PM answer 2, S8).
    case negative
    /// More decimal places than the currency has (JPY 0, INR 2, KWD 3).
    case tooManyDecimals(allowed: Int)
    /// Larger than the store can hold exactly.
    case outOfRange
}

/// Parses an amount typed in the account form, in the device's number format.
///
/// Grouping uses the locale's separators and must be well formed, so a misplaced separator fails instead of
/// changing the amount: the last group before the decimal separator has 3 digits, the first 1–3, and the groups
/// between are all 3 (125,000 or 1,234,567) or, for Indian lakh grouping, all 2 (1,25,000 or 1,00,00,000).
/// "10,00" or "1,5" in en_US and "1.5" in de_DE are rejected. Ungrouped digits always work.
///
/// A currency symbol, the ISO code and spaces around the number are ignored, so a pasted "₹1,25,000.00" still
/// parses. Spaces inside the number count as grouping only where the locale groups with a space (fr_FR).
/// An empty field is 0.
public enum AmountInput {
    public static func parse(
        _ text: String,
        currencyCode: String,
        locale: Locale,
    ) throws(AmountInputError) -> Decimal {
        let code = CurrencyCode.normalize(currencyCode)
        var stripped = text.replacingOccurrences(of: code, with: "")
        stripped.unicodeScalars.removeAll { $0.properties.generalCategory == .currencySymbol }
        let cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return 0
        }
        if cleaned.contains(where: { "-−‐–(".contains($0) }) {
            throw .negative
        }
        let (integerDigits, fractionDigits) = try digits(
            in: cleaned,
            decimalSeparator: locale.decimalSeparator?.first ?? ".",
            groupingSeparator: locale.groupingSeparator?.first ?? ",",
        )
        guard let allowed = CurrencyCode.minorUnits(for: code) else {
            throw .notANumber
        }
        if fractionDigits.count > allowed {
            throw .tooManyDecimals(allowed: allowed)
        }
        let plain = (integerDigits.isEmpty ? "0" : integerDigits) + (fractionDigits.isEmpty ? "" : "." + fractionDigits)
        guard let value = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else {
            throw .notANumber
        }
        do {
            try MinorUnitDecimal.validate(value, currencyCode: code)
        } catch {
            throw .outOfRange
        }
        return value
    }

    /// Splits `text` into integer and fraction digits, checking where the grouping separators are.
    private static func digits(
        in text: String,
        decimalSeparator: Character,
        groupingSeparator: Character,
    ) throws(AmountInputError) -> (integer: String, fraction: String) {
        let groupsWithSpace = groupingSeparator.isWhitespace
        let parts = text.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        guard parts.count <= 2 else {
            throw .notANumber
        }
        let groups = parts[0]
            .split(omittingEmptySubsequences: false) { character in
                groupsWithSpace ? character.isWhitespace : character == groupingSeparator
            }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard groups.allSatisfy(isDigits), isDigits(fraction[...]), isWellGrouped(groups) else {
            throw .notANumber
        }
        let integer = groups.joined()
        if integer.isEmpty && fraction.isEmpty {
            throw .notANumber
        }
        return (integer, fraction)
    }

    private static func isDigits(_ text: Substring) -> Bool {
        text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Western (1,234,567) or Indian lakh (12,34,567) grouping. One group means no grouping at all.
    private static func isWellGrouped(_ groups: [Substring]) -> Bool {
        guard groups.count > 1 else {
            return true
        }
        guard let first = groups.first, let last = groups.last, (1...3).contains(first.count), last.count == 3 else {
            return false
        }
        let middle = groups.dropFirst().dropLast()
        if middle.allSatisfy({ $0.count == 3 }) {
            return true
        }
        return first.count <= 2 && middle.allSatisfy { $0.count == 2 }
    }
}
