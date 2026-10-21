import Foundation

/// User-facing text from this package's String Catalog (`Resources/Localizable.xcstrings`), for text built
/// in view models rather than in SwiftUI views.
///
/// Linux, where CI builds and tests the package, has no `String(localized:)`, so there the same call reads
/// the English source text. Interpolated numbers and names fill the catalog's `%lld` and `%@` placeholders.
///
/// `format` is for entries whose key spells out positional arguments (`%1$@`, `%2$lld`), so a translation
/// can put them in any order. Its key is also the English text.
enum FeatureText {
    #if canImport(Darwin)
        typealias Value = String.LocalizationValue

        static func string(_ value: Value, comment: StaticString) -> String {
            String(localized: value, bundle: .module, comment: comment)
        }

        /// The catalog entry `key`, filled with `arguments`. The catalog holds its comment and any plural
        /// variants; a missing entry falls back to `key`, the English text.
        static func format(_ key: StaticString, _ arguments: any CVarArg...) -> String {
            let format = Bundle.module.localizedString(forKey: "\(key)", value: nil, table: nil)
            return String(format: format, locale: .current, arguments: arguments)
        }

        /// The catalog entry `key`, whose plural variants are chosen by `count`. `one` is the English
        /// singular, for Linux, which has no catalog.
        static func plural(_ key: StaticString, one _: StaticString, _ count: Int) -> String {
            format(key, count)
        }
    #else
        /// The English text, built from the same interpolated literal as on Apple platforms.
        struct Value: ExpressibleByStringInterpolation {
            let text: String

            init(stringLiteral value: String) {
                text = value
            }

            init(stringInterpolation: DefaultStringInterpolation) {
                text = stringInterpolation.description
            }
        }

        static func string(_ value: Value, comment _: StaticString) -> String {
            value.text
        }

        static func format(_ key: StaticString, _ arguments: any CVarArg...) -> String {
            String(format: "\(key)", locale: .current, arguments: arguments)
        }

        static func plural(_ key: StaticString, one: StaticString, _ count: Int) -> String {
            String(format: count == 1 ? "\(one)" : "\(key)", locale: .current, count)
        }
    #endif
}
