import Foundation

/// Which character a file uses before the decimals. Thousands separators are the other one, or spaces.
public enum ImportDecimalSeparator: String, CaseIterable, Sendable, Codable {
    /// `1,234.56`, `1,25,000.00`
    case period
    /// `1.234,56`, `1 250,00`
    case comma
}

/// Reads money as exact `Decimal`, never `Double` (#11).
///
/// Accepted: an optional sign (`-`, `−`, `+`, or a trailing `-`), parentheses for a negative, a currency symbol,
/// `Rs` or an ISO code before or after the number, and thousands grouping that is valid: no grouping, Western
/// groups of three (`1,234,567.89`), or Indian lakh grouping with the last group of three and the rest in twos
/// (`12,34,567.89`, D39.2). Spaces, no-break spaces and apostrophes group in threes only. Anything else isn't
/// read, so a value is never imported silently wrong (#30 S31).
public enum ImportAmountParser {
    /// The signed amount, or `nil` when the text isn't a readable amount. Empty text is `nil` too; the caller
    /// tells a missing amount from an unreadable one.
    public static func parse(_ text: String, decimalSeparator: ImportDecimalSeparator) -> Decimal? {
        guard var body = cleaned(text) else {
            return nil
        }
        var negative = false
        var signs = 0
        if body.hasPrefix("(") && body.hasSuffix(")") {
            negative = true
            signs += 1
            body = String(body.dropFirst().dropLast())
        }
        // Signs and currency markers can come in either order on either side: "-₹1,250", "₹-1,250", "1250 INR-".
        var changed = true
        while changed {
            changed = false
            body = body.trimmingCharacters(in: spaces)
            if let first = body.first, "-−+".contains(first) {
                if first != "+" {
                    negative = true
                }
                signs += 1
                body.removeFirst()
                changed = true
            } else if let last = body.last, "-−".contains(last) {
                negative = true
                signs += 1
                body.removeLast()
                changed = true
            } else if let stripped = strippingCurrency(body) {
                body = stripped
                changed = true
            }
        }
        guard signs <= 1, let magnitude = number(body, decimalSeparator: decimalSeparator) else {
            return nil
        }
        return negative ? -magnitude : magnitude
    }

    /// The separator the samples point to, or `nil` when every sample reads the same either way (`1,234`,
    /// `500`). A sample with both characters settles it by the last one; `1,5` or `12,50` means a decimal comma,
    /// `1.5` or `12.50` a decimal period, and `1.234.567` grouping dots.
    public static func detectSeparator(_ samples: [String]) -> ImportDecimalSeparator? {
        var periodVotes = 0
        var commaVotes = 0
        for sample in samples {
            switch vote(sample) {
            case .period?: periodVotes += 1
            case .comma?: commaVotes += 1
            case nil: break
            }
        }
        if periodVotes == 0 && commaVotes == 0 {
            return nil
        }
        return commaVotes > periodVotes ? .comma : .period
    }

    /// What one sample says about the separator, or `nil` when it reads the same either way.
    private static func vote(_ sample: String) -> ImportDecimalSeparator? {
        guard let body = cleaned(sample)?.filter({ $0.isNumber || $0 == "." || $0 == "," }) else {
            return nil
        }
        let periods = body.filter { $0 == "." }.count
        let commas = body.filter { $0 == "," }.count
        switch (periods, commas) {
        case (0, 0):
            return nil
        case (1..., 1...):
            let lastPeriod = body.lastIndex(of: ".") ?? body.startIndex
            let lastComma = body.lastIndex(of: ",") ?? body.startIndex
            return lastPeriod > lastComma ? .period : .comma
        case (2..., 0):
            return .comma
        case (0, 2...):
            return .period
        case (1, 0):
            return digitsAfter(".", in: body) == 3 ? nil : .period
        default:
            return digitsAfter(",", in: body) == 3 ? nil : .comma
        }
    }

    /// The separator `locale` writes decimals with, for files that don't settle it.
    public static func separator(for locale: Locale) -> ImportDecimalSeparator {
        locale.decimalSeparator == "," ? .comma : .period
    }

    private static let spaces = CharacterSet(charactersIn: " \t\u{00A0}\u{202F}")

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: spaces.union(.whitespacesAndNewlines))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func digitsAfter(_ separator: Character, in body: String) -> Int {
        guard let index = body.lastIndex(of: separator) else {
            return 0
        }
        return body[body.index(after: index)...].count
    }

    /// `body` without one leading or trailing currency marker, or `nil` when it has none.
    private static func strippingCurrency(_ body: String) -> String? {
        if let first = body.unicodeScalars.first, first.properties.generalCategory == .currencySymbol {
            return String(body.unicodeScalars.dropFirst())
        }
        if let last = body.unicodeScalars.last, last.properties.generalCategory == .currencySymbol {
            return String(body.unicodeScalars.dropLast())
        }
        for marker in ["Rs.", "Rs"] where body.hasPrefix(marker) {
            return String(body.dropFirst(marker.count))
        }
        let letters = body.prefix { $0.isLetter }
        if letters.count == 3, CurrencyCode.minorUnits(for: String(letters)) != nil {
            return String(body.dropFirst(3))
        }
        let trailing = body.reversed().prefix { $0.isLetter }
        if trailing.count == 3, CurrencyCode.minorUnits(for: String(trailing.reversed())) != nil {
            return String(body.dropLast(3))
        }
        return nil
    }

    private static func number(_ body: String, decimalSeparator: ImportDecimalSeparator) -> Decimal? {
        let decimal: Character = decimalSeparator == .period ? "." : ","
        let parts = body.split(separator: decimal, omittingEmptySubsequences: false)
        guard parts.count <= 2 else {
            return nil
        }
        let integer = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard parts.count == 1 || !fraction.isEmpty, fraction.allSatisfy(\.isASCIIDigit) else {
            return nil
        }
        guard let digits = integerDigits(integer, decimalSeparator: decimalSeparator) else {
            return nil
        }
        guard !digits.isEmpty || !fraction.isEmpty else {
            return nil
        }
        let plain = (digits.isEmpty ? "0" : digits) + (fraction.isEmpty ? "" : "." + fraction)
        return Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The integer part's digits once valid grouping is taken out, or `nil` for invalid grouping.
    private static func integerDigits(_ integer: String, decimalSeparator: ImportDecimalSeparator) -> String? {
        if integer.allSatisfy(\.isASCIIDigit) {
            return integer
        }
        let groupMark: Character = decimalSeparator == .period ? "," : "."
        let separators = integer.filter { !$0.isASCIIDigit }
        guard let separator = separators.first, separators.allSatisfy({ $0 == separator }) else {
            return nil
        }
        let allowsLakh = separator == groupMark
        guard allowsLakh || " \u{00A0}\u{202F}'".contains(separator) else {
            return nil
        }
        let groups = integer.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }), groups.count >= 2 else {
            return nil
        }
        let last = groups[groups.count - 1]
        let middle = groups.dropFirst().dropLast()
        let first = groups[0]
        let western = (1...3).contains(first.count) && middle.allSatisfy { $0.count == 3 } && last.count == 3
        let lakh =
            allowsLakh && (1...2).contains(first.count) && middle.allSatisfy { $0.count == 2 } && last.count == 3
        guard western || lakh else {
            return nil
        }
        return groups.joined()
    }
}

extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
