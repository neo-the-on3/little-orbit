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
}
