import Foundation

/// ISO 4217 alphabetic codes and their minor-unit exponents.
///
/// Money stays `Decimal` in the domain. Persistence stores an integer number of minor units plus this scale,
/// which is exact for every amount the validator accepts (JPY 0, USD/INR 2, KWD 3).
public enum CurrencyCode {
    public static let fallback = "USD"

    /// Currency for a new account: the device locale when it is a known ISO code, otherwise USD.
    public static var deviceDefault: String {
        if let identifier = Locale.current.currency?.identifier {
            let code = normalize(identifier)
            if minorUnits(for: code) != nil {
                return code
            }
        }
        return fallback
    }

    public static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func minorUnits(for code: String) -> Int? {
        exponents[normalize(code)]
    }

    public static func validate(_ code: String) throws -> String {
        let normalized = normalize(code)
        guard minorUnits(for: normalized) != nil else {
            throw LedgerValidationError.invalidCurrencyCode
        }
        return normalized
    }

    /// Active ISO 4217 alphabetic codes. Exponents follow the standard minor units.
    private static let exponents: [String: Int] = {
        var table: [String: Int] = [:]
        func add(_ scale: Int, _ codes: [String]) {
            for code in codes {
                table[code] = scale
            }
        }
        add(
            0,
            [
                "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV",
                "XAF", "XOF", "XPF",
            ],
        )
        add(3, ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"])
        add(4, ["CLF", "UYW"])
        add(
            2,
            [
                "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN", "BAM", "BBD", "BDT", "BGN",
                "BMD", "BND", "BOB", "BOV", "BRL", "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHE", "CHF",
                "CHW", "CNY", "COP", "COU", "CRC", "CUP", "CVE", "CZK", "DKK", "DOP", "DZD", "EGP", "ERN", "ETB",
                "EUR", "FJD", "FKP", "GBP", "GEL", "GHS", "GIP", "GMD", "GTQ", "GYD", "HKD", "HNL", "HTG", "HUF",
                "IDR", "ILS", "INR", "IRR", "JMD", "KES", "KGS", "KHR", "KPW", "KYD", "KZT", "LAK", "LBP", "LKR",
                "LRD", "LSL", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP", "MRU", "MUR", "MVR", "MWK", "MXN",
                "MXV", "MYR", "MZN", "NAD", "NGN", "NIO", "NOK", "NPR", "NZD", "PAB", "PEN", "PGK", "PHP", "PKR",
                "PLN", "QAR", "RON", "RSD", "RUB", "SAR", "SBD", "SCR", "SDG", "SEK", "SGD", "SHP", "SLE", "SOS",
                "SRD", "SSP", "STN", "SVC", "SYP", "SZL", "THB", "TJS", "TMT", "TOP", "TRY", "TTD", "TWD", "TZS",
                "UAH", "USD", "USN", "UYU", "UZS", "VED", "VES", "WST", "XCD", "YER", "ZAR", "ZMW", "ZWG", "ZWL",
            ],
        )
        return table
    }()
}
