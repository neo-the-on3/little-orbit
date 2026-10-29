import Foundation
import LittleOrbitDomain

/// The Match step's rows: the names in the file and what each can be matched to.
extension CSVImportViewModel {
    // Built with the plan, each list of options sorted once (`matchSections`), so drawing Match does no
    // per-row work.

    public var accountMatches: [ImportMatchRow] {
        matchSections.accounts
    }

    public var categoryMatches: [ImportMatchRow] {
        matchSections.categories
    }

    public var payeeMatches: [ImportMatchRow] {
        matchSections.payees
    }

    /// The Match step's notes about currencies, only for a Debit & Credit file.
    public var accountsHeaderNote: String? {
        isDebitAndCredit ? ImportExportText.newAccountCurrencyNote : nil
    }

    public var accountsFooterNote: String? {
        isDebitAndCredit ? ImportExportText.differentCurrenciesNote : nil
    }

    /// The same no-currency-column note, under the accounts, whenever a non-Debit & Credit file offers a
    /// new account's currency picker (D454.2): no column mapped to Currency and a new account. Matching
    /// that account to an existing one, or mapping a currency column, takes it away with the picker.
    public var newAccountCurrencyFootnote: String? {
        guard !isDebitAndCredit, matchSections.accounts.contains(where: { $0.newAccountCurrency != nil }) else {
            return nil
        }
        return ImportExportText.newAccountCurrencyNote
    }
}
