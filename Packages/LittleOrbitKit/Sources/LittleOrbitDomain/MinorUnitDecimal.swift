import Foundation

/// Exact `Decimal` storage as an integer number of minor units plus a scale.
///
/// SwiftData's CloudKit path is reliable for integer attributes. A `Decimal` attribute is not, so the store keeps
/// `minorUnits` and `scale` and the domain converts at the repository boundary. Scale 2 stores 750.10 as 75010.
public enum MinorUnitDecimal {
    public struct Stored: Equatable, Sendable, Hashable {
        public var minorUnits: Int64
        public var scale: Int16

        public init(minorUnits: Int64, scale: Int16) {
            self.minorUnits = minorUnits
            self.scale = scale
        }
    }

    public static func store(_ value: Decimal, scale: Int) throws -> Stored {
        guard (0...18).contains(scale) else {
            throw LedgerValidationError.tooManyDecimalPlaces
        }
        let factor = powerOfTen(scale)
        let product = value * factor
        var source = product
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard rounded == product else {
            throw LedgerValidationError.tooManyDecimalPlaces
        }
        let minorUnits = try int64(from: rounded)
        return Stored(minorUnits: minorUnits, scale: Int16(scale))
    }

    public static func decimal(from stored: Stored) -> Decimal {
        let scale = Int(stored.scale)
        let magnitude = powerOfTen(abs(scale))
        if scale >= 0 {
            return Decimal(stored.minorUnits) / magnitude
        }
        return Decimal(stored.minorUnits) * magnitude
    }

    public static func fractionalDigits(in value: Decimal) -> Int {
        if value == 0 {
            return 0
        }
        for digits in 0...38 {
            var source = value
            var rounded = Decimal()
            NSDecimalRound(&rounded, &source, digits, .plain)
            if rounded == value {
                return digits
            }
        }
        return 38
    }

    public static func validate(_ value: Decimal, currencyCode: String) throws {
        guard let scale = CurrencyCode.minorUnits(for: currencyCode) else {
            throw LedgerValidationError.invalidCurrencyCode
        }
        if fractionalDigits(in: value) > scale {
            throw LedgerValidationError.tooManyDecimalPlaces
        }
        _ = try store(value, scale: scale)
    }

    private static func powerOfTen(_ scale: Int) -> Decimal {
        var result = Decimal(1)
        if scale > 0 {
            for _ in 0..<scale {
                result *= 10
            }
        }
        return result
    }

    private static func int64(from integral: Decimal) throws -> Int64 {
        let number = NSDecimalNumber(decimal: integral)
        let plain = number.description(withLocale: Locale(identifier: "en_US_POSIX"))
        guard let value = Int64(plain), NSDecimalNumber(value: value) == number else {
            throw LedgerValidationError.amountOutOfRange
        }
        return value
    }
}
