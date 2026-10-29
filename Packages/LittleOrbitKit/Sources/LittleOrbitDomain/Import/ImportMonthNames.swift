import Foundation

/// The month names a file's dates are read with (#189 I15, D387.6): English always, and the device's language
/// too, full or short, in any case. Only the language counts, never the region (#60 AM8), so `de-CH` and
/// `de-IN` read the same names. When a name means different months in the two languages, English wins.
public struct ImportMonthNames: Equatable, Sendable {
    private let table: [String: Int]

    /// English names only.
    public static let english = ImportMonthNames(table: englishTable)

    /// English and the device's first preferred language.
    public static let device = ImportMonthNames(preferredLanguage: Locale.preferredLanguages.first)

    /// English and the language of `preferredLanguage`, a tag such as `de-DE`. Its region is ignored.
    public init(preferredLanguage: String?) {
        let code = preferredLanguage.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        guard let code, code != "en" else {
            self.init(table: Self.englishTable)
            return
        }
        var table = Self.englishTable
        for (name, month) in Self.names(language: code) where table[name] == nil {
            table[name] = month
        }
        self.init(table: table)
    }

    private init(table: [String: Int]) {
        self.table = table
    }

    /// The month, 1–12, that `name` names, or `nil`. Case and trailing dots don't matter.
    public func month(_ name: String) -> Int? {
        table[Self.key(name)]
    }

    private static func key(_ name: String) -> String {
        String(name.lowercased().reversed().drop { $0 == "." }.reversed())
    }

    private static let englishTable: [String: Int] = {
        let short = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let full = [
            "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
            "november", "december",
        ]
        var table: [String: Int] = ["sept": 9]
        for index in short.indices {
            table[short[index]] = index + 1
            table[full[index]] = index + 1
        }
        return table
    }()

    /// Full and short names, in the form used in dates and the stand-alone form (Russian `ноября`, `ноябрь`).
    private static func names(language code: String) -> [String: Int] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: code)
        formatter.calendar = Calendar(identifier: .gregorian)
        let lists: [[String]] = [
            formatter.monthSymbols, formatter.shortMonthSymbols, formatter.standaloneMonthSymbols,
            formatter.shortStandaloneMonthSymbols,
        ]
        var table: [String: Int] = [:]
        for list in lists where list.count == 12 {
            for (index, name) in list.enumerated() {
                let key = key(name)
                // A name made only of digits would read as a number, so it's skipped.
                if !key.isEmpty, !key.allSatisfy(\.isASCIIDigit), table[key] == nil {
                    table[key] = index + 1
                }
            }
        }
        return table
    }
}
