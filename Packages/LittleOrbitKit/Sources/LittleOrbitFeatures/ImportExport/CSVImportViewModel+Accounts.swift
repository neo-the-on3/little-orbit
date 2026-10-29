import Foundation
import LittleOrbitDomain

/// The target account step and the Match step's choices.
extension CSVImportViewModel {
    // MARK: Target account

    /// Whether the file names no account, so its rows need one chosen.
    public var needsTargetAccount: Bool {
        mapping.column(for: .account) == nil
    }

    public var accountOptions: [ImportMatchOption] {
        ledger.accounts.sorted { $0.sortOrder < $1.sortOrder }.map { ImportMatchOption(id: $0.id, name: $0.name) }
    }

    public var targetAccountID: UUID? {
        get { choices.targetAccountID }
        set {
            choices.targetAccountID = newValue
            settingChanged(owner: needsTargetAccount ? .account : .columns)
        }
    }

    // MARK: Match

    public func setChoice(_ choice: ImportMatchChoice, for key: ImportMatchKey) async {
        choices.matches[key] = choice
        await plan()
    }
}
