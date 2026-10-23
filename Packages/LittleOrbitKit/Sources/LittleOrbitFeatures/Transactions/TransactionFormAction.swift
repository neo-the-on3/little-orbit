import Foundation

/// Edit Expense's buttons that act on the stored record (#34).
public enum TransactionFormAction: Hashable, Sendable, CaseIterable {
    case refund
    case duplicate
    case delete

    /// With unsaved edits, Refund… and Duplicate first ask to discard them, and do nothing unless that's
    /// confirmed. Delete never asks: it runs the normal single delete, which is undoable (D242.4).
    public var asksToDiscardEdits: Bool {
        self != .delete
    }
}
