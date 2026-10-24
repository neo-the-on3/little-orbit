import Foundation
import LittleOrbitDomain

/// One account in the bulk sheet's Account popup. An account no row can move to is shown but disabled, with why
/// (D223.2, D226.3).
public struct BulkAccountOption: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var currencyCode: String
    /// "To account of a selected transfer", or "Not in INR"; `nil` when every row can move to it.
    public var disabledReason: String?

    public var isEnabled: Bool { disabledReason == nil }
}

extension BulkEditViewModel {
    /// The currencies the selected rows are in, a transfer by its From account (D17, D226.2).
    private var selectionCurrencies: Set<String> {
        Set(selection.compactMap { row in accounts.first { $0.id == row.accountID }?.currencyCode })
    }

    /// `false` when the selection mixes currencies, so no account can take every row (D223.2, D226.3).
    public var isAccountEnabled: Bool { selectionCurrencies.count <= 1 }

    /// The Account popup's text: the chosen account, or "Mixed currencies" when Account is unavailable.
    public var accountPopupText: String {
        guard isAccountEnabled else {
            return BulkEditText.mixedCurrencies
        }
        return accounts.first { $0.id == accountID }?.name ?? ""
    }

    /// The one footnote under Account, shown when an account is disabled or Account is unavailable (D226.3).
    public var accountFootnote: String? {
        guard !isAccountEnabled || accountOptions.contains(where: { !$0.isEnabled }) else {
            return nil
        }
        return BulkEditRules.includesTransfers(selection)
            ? BulkEditText.accountRuleWithTransfer : BulkEditText.accountRule
    }

    /// The visible accounts in sidebar order. A selected transfer's To account is disabled first; then, for a
    /// selection in one currency, every account in another (D223.2, D226.3).
    static func accountOptions(for selection: [Transaction], accounts: [Account]) -> [BulkAccountOption] {
        let currencies = Set(selection.compactMap { row in accounts.first { $0.id == row.accountID }?.currencyCode })
        let toAccounts = Set(selection.filter { $0.type == .transfer }.compactMap(\.transferAccountID))
        return accounts.filter { !$0.isHidden && $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
            .map { account in
                var reason: String?
                if toAccounts.contains(account.id) {
                    reason = BulkEditText.ownToAccount
                } else if currencies.count == 1, let currency = currencies.first, account.currencyCode != currency {
                    reason = BulkEditText.notIn(currency)
                }
                return BulkAccountOption(
                    id: account.id,
                    name: account.name,
                    currencyCode: account.currencyCode,
                    disabledReason: reason,
                )
            }
    }
}
