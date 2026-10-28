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
    /// Scheduled items lock their accounts' currency in Edit Account (D381.3).
    private let plannedItems: any PlannedItemsSource

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
        self.plannedItems = plannedItems
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
            scheduledAccountIDs: scheduledAccountIDs(locking: mode),
            changed: { [weak updates] in updates?.changed() },
        )
    }

    /// The accounts scheduled items use (D381.3). When they can't be read, the account being edited counts as one
    /// of them, so its currency shows locked with the usual message: the lock fails closed (Tech Architect n1).
    /// The store refuses the change either way (D410.1).
    private func scheduledAccountIDs(locking mode: AccountFormMode) -> Set<UUID> {
        do {
            return try plannedItems.scheduledAccountIDs()
        } catch {
            guard case .edit(let id) = mode else {
                return []
            }
            return [id]
        }
    }
}
