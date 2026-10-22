import LittleOrbitDomain

extension LedgerUpdates {
    /// Clears every window's undo history and reloads every window each time a restore replaces the ledger
    /// (D187.2, Tech Architect N6). The composition root calls this once, with the `LedgerChanges` the backup
    /// service signals.
    public func follow(_ changes: LedgerChanges) {
        changes.onReplacement { [weak self] in
            self?.ledgerReplaced()
        }
    }
}
