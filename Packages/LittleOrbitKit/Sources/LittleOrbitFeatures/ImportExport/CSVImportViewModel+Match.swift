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
    /// Reuses D387’s catalog copy under the generic file’s new-account currency picker (D454.2).
    public var newAccountCurrencyFootnote: String? {
        guard !isDebitAndCredit, matchSections.accounts.contains(where: { $0.newAccountCurrency != nil }) else {
            return nil
        }
        return ImportExportText.newAccountCurrencyNote
    }
}
