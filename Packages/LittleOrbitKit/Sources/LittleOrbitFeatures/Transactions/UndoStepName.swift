import Foundation
import LittleOrbitDomain

/// The name a step is registered with: the user's action and where it happened, on every screen and in
/// every window (D198, superseding D162.2's on-screen rule and the screen-dependent parts of D165.1, D166.1
/// and D187.3). Each shape is one whole phrase in the String Catalog, with plural rules, so a translation
/// never joins pieces: "Delete Transaction in Household Card", "Delete 5 Transactions in 2 Accounts",
/// "Edit Transfer from Household Card to Everyday Savings".
extension UndoActionTitle {
    private enum Action {
        case new, edit, delete
    }

    /// The registered name of `change`, with where it happened from `impact`. The account names are the ones
    /// when the step is recorded; a later rename doesn't change them (D198). A whole-account step keeps
    /// `base(of:)`, which already names the account, and so does a change that touched no account.
    public static func stepName(of change: TransactionChange, impact: ChangeImpact) -> String {
        let accounts = unique(impact.accounts)
        guard !accounts.isEmpty else {
            return base(of: change)
        }
        let action: Action
        let count: Int
        let isTransfer: Bool
        switch change {
        case .removed(let items):
            (action, count) = (.delete, items.count)
            isTransfer = items.count == 1 && items[0].transaction.type == .transfer
        case .added(let ids):
            (action, count) = (.new, ids.count)
            isTransfer = ids.count == 1 && impact.transfers.contains { $0.transactionID == ids[0] }
        case .replaced(let items):
            (action, count) = (.edit, items.count)
            isTransfer = items.count == 1 && items[0].type == .transfer
        case .removedAccount, .addedAccount:
            return base(of: change)
        }
        if count != 1 {
            return several(action, count, accounts)
        }
        if isTransfer {
            if let route = route(of: impact) {
                return transfer(action, from: route.source.name, to: route.destination.name)
            }
            return transfer(action, accounts)
        }
        return single(action, accounts)
    }

    private static func single(_ action: Action, _ accounts: [Account]) -> String {
        if accounts.count == 1 {
            let name = accounts[0].name
            return switch action {
            case .new: FeatureText.format("New Transaction in %@", name)
            case .edit: FeatureText.format("Edit Transaction in %@", name)
            case .delete: FeatureText.format("Delete Transaction in %@", name)
            }
        }
        // An edit that moved the transaction to another account.
        return switch action {
        case .new: FeatureText.format("New Transaction in %lld Accounts", accounts.count)
        case .edit: FeatureText.format("Edit Transaction in %lld Accounts", accounts.count)
        case .delete: FeatureText.format("Delete Transaction in %lld Accounts", accounts.count)
        }
    }

    private static func transfer(_ action: Action, from source: String, to destination: String) -> String {
        switch action {
        case .new: FeatureText.format("New Transfer from %1$@ to %2$@", source, destination)
        case .edit: FeatureText.format("Edit Transfer from %1$@ to %2$@", source, destination)
        case .delete: FeatureText.format("Delete Transfer from %1$@ to %2$@", source, destination)
        }
    }

    /// A transfer without its two accounts: moved to another account (D166.3), or one of them deleted.
    private static func transfer(_ action: Action, _ accounts: [Account]) -> String {
        if accounts.count == 1 {
            let name = accounts[0].name
            return switch action {
            case .new: FeatureText.format("New Transfer in %@", name)
            case .edit: FeatureText.format("Edit Transfer in %@", name)
            case .delete: FeatureText.format("Delete Transfer in %@", name)
            }
        }
        return switch action {
        case .new: FeatureText.format("New Transfer in %lld Accounts", accounts.count)
        case .edit: FeatureText.format("Edit Transfer in %lld Accounts", accounts.count)
        case .delete: FeatureText.format("Delete Transfer in %lld Accounts", accounts.count)
        }
    }

    /// A bulk change, counting both accounts of each transfer (D166.4).
    private static func several(_ action: Action, _ count: Int, _ accounts: [Account]) -> String {
        if accounts.count == 1 {
            let name = accounts[0].name
            return switch action {
            case .new: FeatureText.format("Add %1$lld Transactions in %2$@", count, name)
            case .edit: FeatureText.format("Edit %1$lld Transactions in %2$@", count, name)
            case .delete: FeatureText.format("Delete %1$lld Transactions in %2$@", count, name)
            }
        }
        return switch action {
        case .new: FeatureText.format("Add %1$lld Transactions in %2$lld Accounts", count, accounts.count)
        case .edit: FeatureText.format("Edit %1$lld Transactions in %2$lld Accounts", count, accounts.count)
        case .delete: FeatureText.format("Delete %1$lld Transactions in %2$lld Accounts", count, accounts.count)
        }
    }
}
