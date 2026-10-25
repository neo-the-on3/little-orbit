import Foundation
import LittleOrbitDomain

/// What a Debit & Credit import (#60) says on top of the shared CSV import screens.
extension ImportExportText {
    // MARK: Columns

    static var debitAndCreditDetected: String {
        FeatureText.string(
            "Debit & Credit export detected. Every column is mapped; you can still change any of them. Extra columns are ignored.",
            comment:
                "CSV import Columns step: the note when the file’s header is a Debit & Credit export (D44). “Debit & Credit” is another app’s name.",
        )
    }

    /// The layout a Debit & Credit date has to be in, for “Date can’t be read as …”.
    static var debitAndCreditDateFormat: String {
        FeatureText.string(
            "YYYY-MM-DD HH:mm:ss",
            comment: "CSV import: the date and time layout of a Debit & Credit export, named in a row issue.",
        )
    }

    // MARK: Row issues

    /// #60's own wording where it differs from #30's: “Unrecognised amount” (D38.2, D39.1, AM12) and
    /// “Transfer Account must differ from Account”, which names the format's column (D111).
    static func debitAndCreditIssue(_ issue: ImportRowIssue) -> String {
        switch issue {
        case .unreadableAmount, .tooManyDecimalPlaces:
            FeatureText.string(
                "Unrecognised amount",
                comment:
                    "Debit & Credit import row issue (D38.2): the amount isn’t a number this format allows, or has more decimals than the account’s currency.",
            )
        case .sameTransferAccount:
            FeatureText.string(
                "Transfer Account must differ from Account",
                comment:
                    "Debit & Credit import row issue (D50, D111): both sides of a transfer are the same account. “Transfer Account” and “Account” are the file’s column names.",
            )
        case .unreadableDate:
            FeatureText.format("Date can’t be read as %@", debitAndCreditDateFormat)
        default:
            Self.issue(issue, dateOrder: .yearMonthDay)
        }
    }

    /// “Rows 4 and 6”: a transfer whose two halves were both in the file (D38.5, TR4).
    static func pairedRows(_ first: Int, _ second: Int) -> String {
        FeatureText.format("Rows %1$lld and %2$lld", first, second)
    }

    /// “received €5,000.00”: the amount a transfer between currencies gives the receiving account (D17).
    static func received(_ amount: String) -> String {
        FeatureText.format("received %@", amount)
    }

    // MARK: Match

    /// “2 rows”: how many file rows use a name on the Match step, both halves of a transfer included.
    static func rowCount(_ count: Int) -> String {
        FeatureText.plural("%lld rows", one: "%lld row", count)
    }

    static var newAccountCurrencyNote: String {
        FeatureText.string(
            "The file has no currency column. A matched account keeps its own currency; a new account uses your region’s currency unless you change it.",
            comment: "Debit & Credit import Match step: the note above the accounts.",
        )
    }

    static var differentCurrenciesNote: String {
        FeatureText.string(
            "If you map accounts with different currencies, a transfer between them needs both halves in the file, so the other half can give the amount received. A transfer with only one half would be listed as an error.",
            comment: "Debit & Credit import Match step: the note under the accounts (D29, D331).",
        )
    }

    // MARK: Review

    static var willBeCreated: String {
        FeatureText.string(
            "Will Be Created",
            comment: "Debit & Credit import Review: the section counting the new accounts, categories and payees.",
        )
    }

    static var newAccounts: String {
        FeatureText.string("New accounts", comment: "Debit & Credit import Review: how many accounts will be created.")
    }

    static var newCategories: String {
        FeatureText.string(
            "New categories",
            comment: "Debit & Credit import Review: how many categories will be created.",
        )
    }

    static var newPayees: String {
        FeatureText.string("New payees", comment: "Debit & Credit import Review: how many payees will be created.")
    }

    static var totalsByAccount: String {
        FeatureText.string(
            "Totals by Account",
            comment: "Debit & Credit import Review: the section of income and expense totals of the ticked rows.",
        )
    }

    static var income: String {
        FeatureText.string(
            "Income",
            comment:
                "A category’s kind, and the Categories screen’s Income tab. Debit & Credit import Review: an account’s income total.",
        )
    }

    static var expense: String {
        FeatureText.string(
            "Expense",
            comment:
                "A category’s kind, and the Categories screen’s Expense tab. Debit & Credit import Review: an account’s expense total.",
        )
    }

    static var totalsFooter: String {
        FeatureText.string(
            "Each total is in the account’s own currency. Transfers aren’t income or expense, so they’re not counted here. Both halves of a transfer in the file become one transfer.",
            comment: "Debit & Credit import Review: the footer under the totals by account.",
        )
    }

    /// D324.2: #60's own Already imported rule, and its notes-shortened count.
    static var debitAndCreditNotSelectedFooter: String {
        let limit = ImportText.noteLimit.formatted()
        return FeatureText.string(
            "Already imported means an exact match: the same account, date and time, amount, type, category and notes. Possible duplicate means the same account, type and amount within 3 days, with a matching payee or description. Both start unticked; tick a row to import it anyway. Notes shortened means notes over \(limit) characters are cut to \(limit). Those rows stay ticked and import.",
            comment:
                "Debit & Credit import Review: the footer under the Not Selected section (D324.2). Both numbers are the notes limit.",
        )
    }
}
