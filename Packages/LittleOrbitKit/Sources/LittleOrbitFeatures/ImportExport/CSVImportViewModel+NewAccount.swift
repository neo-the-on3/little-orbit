import Foundation
import LittleOrbitDomain

extension CSVImportViewModel {
    /// Reuses the account form, but its Save only returns a value: it has no repository to write to.
    public func newAccountForm() -> AccountFormViewModel {
        let deferred = ImportAccountForm(accounts: ledger.accounts)
        return AccountFormViewModel(
            loadAccountForm: deferred,
            saveAccount: deferred,
            mode: .new,
            defaultCurrency: locale.currency?.identifier ?? CurrencyCode.deviceDefault,
            locale: locale,
        )
    }

    public func selectNewAccount(_ account: Account) {
        guard !isClosed, step == .account else { return }
        choices.newTargetAccount = account
        targetAccountID = account.id
    }
}

/// The existing form’s validation and fields, without a write before Import (D387.3).
@MainActor
private struct ImportAccountForm: LoadAccountFormUseCase, SaveAccountUseCase {
    let accounts: [Account]

    func formContext(editing accountID: UUID?, scheduledAccountIDs: Set<UUID>) throws -> AccountFormContext {
        AccountFormContext(accounts: accounts)
    }

    func save(_ draft: AccountDraft, editing accountID: UUID?) throws -> Account {
        guard accountID == nil else { throw AccountUseCaseError.accountNotFound }
        return draft.applied(to: Account(sortOrder: ReorderAccounts.nextSortOrder(after: accounts)))
    }

    func update(_ accountID: UUID, _ change: (inout Account) -> Void) throws {
        throw AccountUseCaseError.accountNotFound
    }
}

extension ImportExportText {
    static var newAccountAction: String {
        FeatureText.string(
            "New Account…",
            comment:
                "CSV import Account step: opens the existing New Account form as a sheet. Nothing is saved until Import.",
        )
    }
}
