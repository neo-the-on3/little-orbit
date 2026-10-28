import Foundation

extension Payee {
    /// The one “touched since” rule (D362, D384) for a payee a change created, where `asLeft` is the payee as
    /// that change stored it: it's untouched only while it's still exactly that record, and not deleted. Normal
    /// Undo, Batch Undo and Undo Import all use it, so they keep and remove the same payees (D384.7).
    ///
    /// Every touch rewrites the record, its `updatedAt` at least: a rename or other edit, archiving or
    /// unarchiving, a default category set or changed (a category merge or delete too), and a transaction or
    /// scheduled item given the payee, even if it's taken off again. So a payee renamed back, or given and then
    /// taken off a transaction, counts as touched and stays. `asLeft` must be read back after the change's own
    /// writes, which set `lastUsedAt` and maybe the default category (`touchPayee`).
    func isUntouched(since asLeft: Payee) -> Bool {
        self == asLeft && deletedAt == nil
    }
}
