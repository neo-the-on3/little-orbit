import Foundation

/// A currency as the account form and the Debit & Credit import's currency picker show it: its code, an em
/// dash and its name in the locale, “INR — Indian Rupee” (D329). One format for both.
enum CurrencyTitle {
    static func title(for code: String, locale: Locale) -> String {
        "\(code) — \(name(for: code, locale: locale))"
    }

    /// The currency's name in the locale, “Indian Rupee”, or its code when the locale has no name for it.
    static func name(for code: String, locale: Locale) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }
}
