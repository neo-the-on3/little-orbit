import Foundation
import LittleOrbitDomain

/// The iOS and iPadOS note after a delete, with Undo (D164.2, D187.7). It belongs to one step of its window's
/// history; any other undoable action closes it, so its Undo can never reverse something else.
public struct UndoToast: Equatable, Sendable {
    public var stepID: UUID
    /// "Deleted Corner Bakery −€4.50", or "5 transactions deleted", plus " in Household Card" off screen.
    public var message: String
    /// The signed amount inside `message`, if any. It never breaks inside: the line breaks around it, and it
    /// scales down only if it alone is wider than the toast (D169, D170 U2).
    public var figure: String?

    /// `message` split around `figure`, with the spaces at the split dropped; `nil` when there is no figure.
    public var figureParts: AccountSubtitle.FigureParts? {
        AccountSubtitle(text: message, isWarning: false, figure: figure).figureParts
    }

    /// The account delete toast: "Deleted “Travel Card”" (D170 U3).
    public static func message(deletedAccount name: String) -> String {
        "Deleted “\(name)”"
    }

    /// The toast's wording (D164.2). `single` is the row's title and signed amount, for a single delete.
    public static func message(single: (title: String, amount: String)?, count: Int, place: String?) -> String {
        let base: String
        if count == 1, let single {
            base = "Deleted \(single.title) \(single.amount)"
        } else {
            base = "\(count) \(count == 1 ? "transaction" : "transactions") deleted"
        }
        return place.map { "\(base) \($0)" } ?? base
    }
}

/// After an Undo or Redo of a change that isn't on screen: "Restored 5 transactions in Household Card", with
/// Show (D164.3, D187.6). The app never navigates by itself; only Show does.
public struct UndoNotice: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var message: String
    /// Where Show goes; `nil` when there is nothing to show (the account was deleted).
    public var accountID: UUID?
}

/// The alert after an Undo or Redo that couldn't run (D187.5, #93 X1–X10): a stale step, which is removed,
/// or a failure such as a full disk, which keeps the step to try again.
public struct UndoAlert: Equatable, Sendable, Identifiable {
    public var id = UUID()
    /// "Can't Undo Edit Transaction", or "Couldn't Make the Change".
    public var title: String
    /// "Corner Bakery was changed in another window. Nothing was changed."
    public var message: String
}
