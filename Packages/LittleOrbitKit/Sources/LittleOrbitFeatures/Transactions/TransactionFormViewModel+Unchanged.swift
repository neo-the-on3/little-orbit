import Foundation

extension TransactionFormViewModel {
    /// Editing with nothing changed: Save just closes the sheet, writing nothing and recording no step, so
    /// Redo isn't cleared (Tester's #87 B4).
    public var isUnchanged: Bool {
        original != nil && !hasUnsavedInput
    }
}
