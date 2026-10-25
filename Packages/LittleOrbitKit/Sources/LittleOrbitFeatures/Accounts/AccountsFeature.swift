import Foundation
import LittleOrbitDomain

/// Everything the Accounts screens need, built once by the composition root (the App target) from the injected
/// use cases. It owns the list view model and makes a form view model each time a form sheet is requested.
@MainActor
public final class AccountsFeature {
    public let accounts: AccountsViewModel
    private let useCases: AccountUseCases
    private let defaultCurrency: String
    private let locale: Locale
    private let updates: LedgerUpdates?

    /// `ledgerChanges` reloads the list after a restore replaced the ledger, so it never shows, or writes back,
    /// the old data (#40). `updates` tells every window to reload after an account is added, edited, hidden,
    /// reordered or deleted, as a transaction change does, so an open import re-plans (D187.4, D327.1).
    public init(
        useCases: AccountUseCases,
        plannedItems: any PlannedItemsSource = NoPlannedItems(),
        defaultCurrency: String = CurrencyCode.deviceDefault,
        locale: Locale = .current,
        ledgerChanges: LedgerChanges? = nil,
        updates: LedgerUpdates? = nil,
    ) {
        self.useCases = useCases
        self.defaultCurrency = defaultCurrency
        self.locale = locale
        self.updates = updates
        let accounts = AccountsViewModel(
            useCases: useCases,
            plannedItems: plannedItems,
            locale: locale,
            changed: { [weak updates] in updates?.changed() },
        )
        self.accounts = accounts
        ledgerChanges?
            .onReplacement { [weak accounts] in
                accounts?.load()
            }
    }

    /// A new form view model for one sheet.
    public func makeForm(_ mode: AccountFormMode) -> AccountFormViewModel {
        AccountFormViewModel(
            useCases: useCases,
            mode: mode,
            defaultCurrency: defaultCurrency,
            locale: locale,
            changed: { [weak updates] in updates?.changed() },
        )
    }
}
