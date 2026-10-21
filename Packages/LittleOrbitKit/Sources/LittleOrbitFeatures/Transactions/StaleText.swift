import Foundation
import LittleOrbitDomain

/// The wording of the stale-step alert (D187.5, #93 X1–X6). The checks are by value, so a change made outside
/// any window reads the same way.
enum StaleText {
    /// "Can't Undo Edit Transaction": the alert's title, with the step's name as the menu showed it.
    static func cantUndo(_ title: String) -> String {
        FeatureText.string("Can't Undo \(title)", comment: "Alert title: an Undo that can't run. The Undo name.")
    }

    static func cantRedo(_ title: String) -> String {
        FeatureText.string("Can't Redo \(title)", comment: "Alert title: a Redo that can't run. The Redo name.")
    }

    static func changed(_ name: String) -> String {
        FeatureText.string(
            "\(name) was changed in another window. Nothing was changed.",
            comment: "Alert message: Undo or Redo of a record another window changed since. The record's name.",
        )
    }

    static func deleted(_ name: String) -> String {
        FeatureText.string(
            "\(name) was deleted in another window. Nothing was changed.",
            comment: "Alert message: Undo or Redo of a record or account another window deleted. Its name.",
        )
    }

    /// A bulk step with more than one stale record, changed, deleted or both (D189.2).
    static func changedOrDeleted(_ count: Int) -> String {
        FeatureText.format(
            "%lld of these transactions were changed or deleted in another window. Nothing was changed.",
            count,
        )
    }

    static var theTransaction: String {
        FeatureText.string("The transaction", comment: "Alert message subject when a transaction has no name.")
    }

    static var theAccount: String {
        FeatureText.string("The account", comment: "Alert message subject when an account's name is unknown.")
    }

    /// The row's title: the payee, else the description, else the type.
    static func name(of transaction: Transaction, payees: [Payee]) -> String {
        if let payee = payees.first(where: { $0.id == transaction.payeeID }) {
            return payee.name
        }
        if let details = TransactionText.trimmed(transaction.details) {
            return details
        }
        return switch transaction.type {
        case .transfer: FeatureText.string("The transfer", comment: "Alert message subject: an unnamed transfer.")
        default: theTransaction
        }
    }
}
