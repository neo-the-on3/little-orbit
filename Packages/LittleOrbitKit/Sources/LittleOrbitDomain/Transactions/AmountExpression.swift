import Foundation

public enum AmountExpressionError: Error, Equatable, Sendable {
    case divideByZero
    /// The result is below 0. The type sets the direction, so it is never flipped (PM default).
    case negativeResult
    /// Two operators in a row, letters, or a stray separator.
    case malformed
    case tooManyDecimals(allowed: Int)
    case outOfRange
}

/// The entry sheet's calculator: digits, the locale's decimal separator, and + − × ÷ (also - * /).
///
/// × and ÷ bind tighter than + and −. Arithmetic is exact `Decimal`; only a computed result is rounded to the
/// currency's minor units (10 ÷ 3 = 3.33). A plain typed number keeps the strict input rules instead, so
/// "12.345" in INR is rejected, never rounded (#11 validation 7). A trailing operator is ignored, so Save can
/// evaluate a pending sum.
public enum AmountExpression {
    static let operators: [Character: Operator] = [
        "+": .add, "-": .subtract, "−": .subtract, "–": .subtract,
        "*": .multiply, "×": .multiply, "/": .divide, "÷": .divide,
    ]

    enum Operator {
        case add, subtract, multiply, divide

        var bindsTight: Bool { self == .multiply || self == .divide }
    }

    public static func hasOperator(_ text: String) -> Bool {
        text.contains { operators[$0] != nil }
    }

    public static func evaluate(
        _ text: String,
        currencyCode: String,
        locale: Locale,
    ) throws(AmountExpressionError) -> Decimal {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("=") {
            trimmed.removeLast()
        }
        while let last = trimmed.last, operators[last] != nil {
            trimmed.removeLast()
        }
        if trimmed.isEmpty {
            return 0
        }
        let (numbers, ops) = try tokens(trimmed)
        let values = try numbers.map { number throws(AmountExpressionError) in
            try parse(number, currencyCode: currencyCode, locale: locale)
        }
        if ops.isEmpty {
            return values[0]
        }
        let result = try compute(values, ops)
        if result < 0 {
            throw .negativeResult
        }
        return try rounded(result, currencyCode: currencyCode)
    }

    private static func tokens(_ text: String) throws(AmountExpressionError) -> ([String], [Operator]) {
        var numbers: [String] = []
        var ops: [Operator] = []
        var current = ""
        for character in text {
            if let symbol = operators[character] {
                if current.trimmingCharacters(in: .whitespaces).isEmpty {
                    throw .malformed
                }
                numbers.append(current)
                ops.append(symbol)
                current = ""
            } else {
                current.append(character)
            }
        }
        if current.trimmingCharacters(in: .whitespaces).isEmpty {
            throw .malformed
        }
        numbers.append(current)
        return (numbers, ops)
    }

    private static func parse(_ number: String, currencyCode: String, locale: Locale) throws(AmountExpressionError)
        -> Decimal
    {
        do {
            return try AmountInput.parse(number, currencyCode: currencyCode, locale: locale)
        } catch {
            switch error {
            case .tooManyDecimals(let allowed): throw .tooManyDecimals(allowed: allowed)
            case .outOfRange: throw .outOfRange
            case .notANumber, .negative: throw .malformed
            }
        }
    }

    /// Two passes: × ÷ first, then + − left to right.
    private static func compute(_ values: [Decimal], _ ops: [Operator]) throws(AmountExpressionError) -> Decimal {
        var terms: [Decimal] = [values[0]]
        var additive: [Operator] = []
        for (index, symbol) in ops.enumerated() {
            let value = values[index + 1]
            if symbol.bindsTight {
                let left = terms.removeLast()
                if symbol == .divide {
                    if value == 0 {
                        throw .divideByZero
                    }
                    terms.append(left / value)
                } else {
                    terms.append(left * value)
                }
            } else {
                additive.append(symbol)
                terms.append(value)
            }
        }
        var total = terms[0]
        for (index, symbol) in additive.enumerated() {
            total = symbol == .add ? total + terms[index + 1] : total - terms[index + 1]
        }
        return total
    }

    private static func rounded(_ value: Decimal, currencyCode: String) throws(AmountExpressionError) -> Decimal {
        let scale = CurrencyCode.minorUnits(for: currencyCode) ?? 2
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        do {
            try MinorUnitDecimal.validate(result, currencyCode: currencyCode)
        } catch {
            throw .outOfRange
        }
        return result
    }
}
