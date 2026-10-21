import Foundation
import LittleOrbitDomain

/// A calculator key: the operator row above the iOS decimal pad (D163), or a key the macOS field maps.
public enum KeypadKey: Equatable, Sendable {
    case digit(Int)
    case decimal
    case add
    case subtract
    case multiply
    case divide
    case equals
    case backspace
}

/// The entry sheet's calculator state: the sum as typed, the line above it after "=", and any error.
///
/// Digits stop at the currency's decimal places. Pressing an operator twice replaces it. After "=", a digit
/// starts a new amount and an operator carries on from the result.
///
/// When "=" can't work the sum out, the sum stays and the error replaces the result (UI Designer, #87 U4).
/// Keys keep editing it, the error stays until the sum works out again, and "=" does nothing meanwhile.
struct AmountKeypad: Equatable {
    /// Digits, "." and the operators + − × ÷.
    private(set) var expression = ""
    private(set) var line: String?
    private(set) var error: AmountExpressionError?
    private var justEvaluated = false

    static let operators: Set<Character> = ["+", "−", "×", "÷"]
    static let maximumIntegerDigits = 12

    init(amount: Decimal? = nil) {
        expression = amount.map(Self.plain) ?? ""
    }

    var hasOperator: Bool { expression.contains { Self.operators.contains($0) } }

    func text(decimalSeparator: String) -> String {
        var output = ""
        for character in expression {
            if Self.operators.contains(character) {
                output += " \(character) "
            } else if character == "." {
                output += decimalSeparator
            } else {
                output.append(character)
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    func evaluate(currencyCode: String, locale: Locale) throws(AmountExpressionError) -> Decimal {
        let separator = locale.decimalSeparator ?? "."
        let input = expression.replacingOccurrences(of: ".", with: separator)
        return try AmountExpression.evaluate(input, currencyCode: currencyCode, locale: locale)
    }

    mutating func press(_ key: KeypadKey, currencyCode: String, locale: Locale) {
        if error != nil {
            pressWhileInvalid(key, currencyCode: currencyCode, locale: locale)
            return
        }
        apply(key, currencyCode: currencyCode, locale: locale)
    }

    private mutating func pressWhileInvalid(_ key: KeypadKey, currencyCode: String, locale: Locale) {
        if key == .equals {
            return
        }
        error = nil
        apply(key, currencyCode: currencyCode, locale: locale)
        recheck(currencyCode: currencyCode, locale: locale)
    }

    /// Keeps the error while the edited sum still doesn't work out. A trailing operator is ignored, as for
    /// the amount.
    private mutating func recheck(currencyCode: String, locale: Locale) {
        var complete = self
        if let last = complete.expression.last, Self.operators.contains(last) || last == "." {
            complete.expression.removeLast()
        }
        guard !complete.expression.isEmpty else {
            return
        }
        do {
            _ = try complete.evaluate(currencyCode: currencyCode, locale: locale)
        } catch {
            self.error = error
        }
    }

    private mutating func apply(_ key: KeypadKey, currencyCode: String, locale: Locale) {
        switch key {
        case .digit(let digit): type(digit, scale: CurrencyCode.minorUnits(for: currencyCode) ?? 2)
        case .decimal: typeDecimal(scale: CurrencyCode.minorUnits(for: currencyCode) ?? 2)
        case .add: append("+")
        case .subtract: append("−")
        case .multiply: append("×")
        case .divide: append("÷")
        case .equals: equals(currencyCode: currencyCode, locale: locale)
        case .backspace:
            justEvaluated = false
            line = nil
            if !expression.isEmpty {
                expression.removeLast()
            }
        }
    }

    private mutating func type(_ digit: Int, scale: Int) {
        startOverIfEvaluated()
        guard (0...9).contains(digit), canAddDigit(scale: scale) else {
            return
        }
        if currentNumber == "0" {
            expression.removeLast()
        }
        expression += String(digit)
    }

    private mutating func typeDecimal(scale: Int) {
        startOverIfEvaluated()
        guard scale > 0, !currentNumber.contains(".") else {
            return
        }
        expression += currentNumber.isEmpty ? "0." : "."
    }

    /// Replaces the sum with typed text, as in the macOS amount field. Keeps digits, the locale's decimal
    /// separator and operators (+ - − * × / ÷); drops grouping, letters and spaces.
    /// The field hands back the text it shows when focus moves or after "=", so the same sum again changes
    /// nothing and the line above it stays (Tester's #87 recheck, bug 6).
    mutating func replace(with text: String, decimalSeparator: String) {
        let decimal = decimalSeparator.first ?? "."
        let mapped: [Character: Character] = ["-": "−", "*": "×", "/": "÷"]
        var output = ""
        for character in text {
            if character.isASCII, character.isNumber {
                output.append(character)
            } else if character == decimal {
                output.append(".")
            } else if Self.operators.contains(character) || mapped[character] != nil {
                // A leading sign is dropped: the type sets the direction (D163).
                if !output.isEmpty {
                    output.append(mapped[character] ?? character)
                }
            }
        }
        guard output != expression else {
            return
        }
        error = nil
        line = nil
        justEvaluated = false
        expression = output
    }

    /// Shows why a sum can't be saved, as Save does for an unfinished one.
    mutating func reportError(currencyCode: String, locale: Locale) {
        do {
            _ = try evaluate(currencyCode: currencyCode, locale: locale)
        } catch {
            self.error = error
        }
    }

    private var currentNumber: Substring {
        if let index = expression.lastIndex(where: { Self.operators.contains($0) }) {
            return expression[expression.index(after: index)...]
        }
        return expression[...]
    }

    private func canAddDigit(scale: Int) -> Bool {
        let number = currentNumber
        if let dot = number.firstIndex(of: ".") {
            return number.distance(from: dot, to: number.endIndex) - 1 < scale
        }
        return number.count < Self.maximumIntegerDigits
    }

    private mutating func startOverIfEvaluated() {
        if justEvaluated {
            expression = ""
            line = nil
            justEvaluated = false
        }
    }

    private mutating func append(_ symbol: Character) {
        justEvaluated = false
        line = nil
        guard !expression.isEmpty else {
            return
        }
        if let last = expression.last, Self.operators.contains(last) || last == "." {
            expression.removeLast()
        }
        expression.append(symbol)
    }

    private mutating func equals(currencyCode: String, locale: Locale) {
        guard hasOperator else {
            return
        }
        line = text(decimalSeparator: locale.decimalSeparator ?? ".") + " ="
        do {
            expression = Self.plain(try evaluate(currencyCode: currencyCode, locale: locale))
            justEvaluated = true
        } catch {
            self.error = error
        }
    }

    /// "100", "3.33": the value with "." and no grouping, as the keypad edits it.
    static func plain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    static func message(for error: AmountExpressionError) -> String {
        switch error {
        case .negativeResult: "Result is below zero"
        case .divideByZero: "Can't divide by zero"
        case .malformed: "Check the sum and try again."
        case .tooManyDecimals(let allowed): "Use up to \(allowed) decimal places."
        case .outOfRange: "That amount is too large."
        }
    }
}
