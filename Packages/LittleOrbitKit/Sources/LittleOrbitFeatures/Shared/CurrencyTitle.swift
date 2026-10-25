import Foundation

/// A currency as the account form and the Debit & Credit import's currency picker show it: its code, an em
/// dash and its name in the locale, “INR — Indian Rupee” (D329). One format for both.
enum CurrencyTitle {
    static func title(for code: String, locale: Locale) -> String {
        let name = locale.localizedString(forCurrencyCode: code) ?? code
        return "\(code) — \(name)"
    }
}
