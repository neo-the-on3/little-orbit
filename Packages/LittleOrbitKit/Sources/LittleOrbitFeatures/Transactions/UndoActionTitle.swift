import Foundation
import LittleOrbitDomain

/// The screen a window shows, for the toast and the notice (D165.1, D187.3).
public enum UndoScreen: Equatable, Sendable {
    /// One account.
    case account(UUID)
    /// A screen that isn't one account (the home list, All Accounts, search), with the transactions it shows.
    case list(visible: Set<UUID>)
}

/// The Undo and Redo names: what the change was and where it happened (D198, D166, UI Designer), and the
/// toast's and notice's rule for saying where only when it isn't on screen (D165.1). A window's history
/// covers all its accounts, so Undo can reverse a change made on another account. The facts come from the domain's `ChangeImpact`; the
/// wording and the on-screen rules live here.
public enum UndoActionTitle {
    /// The name `UndoManager` shows for the user's change, as in "Undo Delete Transaction" or "Undo Edit 5
    /// Transactions". Bulk changes include the count, so the menus say exactly what will be undone (Kiran's
    /// Q1 on #87). Redo keeps the name of the user's change, not of its inverse (see `WindowUndoHistory`).
    public static func base(of change: TransactionChange) -> String {
        // A payee the save created doesn't change the name: "Undo New Transaction" (D191.4).
        if let type = change.duplicatedType {
            return duplicate(type)
        }
        return switch change.core {
        case .removed(let items):
            if items.count == 1 {
                FeatureText.string("Delete Transaction", comment: "Undo name: one transaction deleted.")
            } else {
                FeatureText.string(
                    "Delete \(items.count) Transactions",
                    comment: "Undo name: several transactions deleted at once.",
                )
            }
        case .added(let ids):
            if ids.count == 1 {
                FeatureText.string("New Transaction", comment: "Undo name: one transaction added.")
            } else {
                FeatureText.string(
                    "Add \(ids.count) Transactions",
                    comment: "Undo name: several transactions added at once.",
                )
            }
        case .replaced(let items):
            if items.count != 1 {
                FeatureText.string(
                    "Edit \(items.count) Transactions",
                    comment: "Undo name: several transactions edited at once.",
                )
            } else if items.first?.type == .transfer {
                FeatureText.string("Edit Transfer", comment: "Undo name: one transfer edited.")
            } else {
                FeatureText.string("Edit Transaction", comment: "Undo name: one transaction edited.")
            }
        case .removedAccount(let removed):
            FeatureText.string(
                "Delete Account \(removed.account.name)",
                comment: "Undo name: an account deleted, with its name.",
            )
        case .addedAccount, .createdPayees, .removedPayees, .restoringLines, .duplicated:
            accountAdded(change.core)
        }
    }

    /// "New Account", for `.addedAccount` only. `core` unwraps the other cases to the change they carry, so
    /// they never get here, and never read "New Account".
    private static func accountAdded(_ core: TransactionChange) -> String {
        guard case .addedAccount = core else {
            preconditionFailure("TransactionChange.core never returns a wrapping case")
        }
        return FeatureText.string("New Account", comment: "Undo name: an account added.")
    }

    /// `base` ("5 transactions deleted") as the toast shows it on `screen`; Undo and Redo names use `stepName`
    /// instead (D198). It is unchanged only when the change is on
    /// screen: every account it touches is the one shown (D165.1), one transfer is viewed from either of its
    /// accounts (D166.1), or a combined list shows all its transactions. Otherwise it reads "… in Household
    /// Card", "… in 2 Accounts" (even viewed from one of them, and counting both accounts of each transfer in a
    /// bulk change, D166.4), or "… from Household Card to Everyday Savings" for one transfer (D166.2). A
    /// transfer moved to another account counts every account before and after (D166.3).
    public static func name(_ base: String, impact: ChangeImpact, on screen: UndoScreen) -> String {
        guard !impact.accounts.isEmpty, isOffScreen(impact, on: screen) else {
            return base
        }
        return placed(base, impact)
    }

    /// `text` with where the change happened: "… from Household Card to Everyday Savings" for one transfer,
    /// otherwise "… in Household Card" or "… in 2 Accounts". Each shape is one catalog entry with positional
    /// arguments, so a translation can put the place first or inflect the action around it. The Undo and Redo
    /// names, the toast and the notice all use it (D166.5).
    public static func placed(_ text: String, _ impact: ChangeImpact) -> String {
        if let route = route(of: impact) {
            return FeatureText.format("%1$@ from %2$@ to %3$@", text, route.source.name, route.destination.name)
        }
        let unique = unique(impact.accounts)
        if unique.count == 1 {
            return FeatureText.format("%1$@ in %2$@", text, unique[0].name)
        }
        return FeatureText.format("%1$@ in %2$lld Accounts", text, unique.count)
    }

    /// Whether any part of the change is somewhere other than `screen` (D165.1, D166).
    public static func isOffScreen(_ impact: ChangeImpact, on screen: UndoScreen) -> Bool {
        switch screen {
        case .account(let id):
            if let route = route(of: impact) {
                return route.source.id != id && route.destination.id != id
            }
            return impact.accounts.contains { $0.id != id }
        case .list(let visible):
            return impact.transactionIDs.contains { !visible.contains($0) }
        }
    }

    /// The two accounts of a change to one transfer that kept them (D166.1, D166.2), from its current
    /// version; `nil` for anything else, including a transfer moved to another account (D166.3).
    static func route(of impact: ChangeImpact) -> (source: Account, destination: Account)? {
        guard let latest = impact.transfers.last,
            impact.transfers.allSatisfy({ $0.transactionID == latest.transactionID }),
            Set(impact.transactionIDs) == [latest.transactionID],
            impact.accountIDs.count == 2,
            let source = impact.accounts.first(where: { $0.id == latest.sourceAccountID }),
            let destination = impact.accounts.first(where: { $0.id == latest.destinationAccountID })
        else {
            return nil
        }
        return (source, destination)
    }

    static func unique(_ accounts: [Account]) -> [Account] {
        var seen = Set<UUID>()
        return accounts.filter { seen.insert($0.id).inserted }
    }
}
