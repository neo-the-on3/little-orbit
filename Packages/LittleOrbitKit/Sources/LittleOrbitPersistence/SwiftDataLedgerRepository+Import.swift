#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain

    /// CSV import (#30): a batch of transactions saved or removed, and Undo Import's created payees removed, in one
    /// pass, through the same `LedgerBook` rules as saving or deleting each.
    extension SwiftDataLedgerRepository {
        public func saveNewTransactions(_ transactions: [Transaction]) throws {
            try mutate { try LedgerBook.savingNewTransactions(transactions, in: $0, now: now()) }
        }

        public func deleteTransactions(ids: [UUID]) throws {
            try mutate { try LedgerBook.deletingTransactions(ids: ids, in: $0, now: now()) }
        }

        /// Undo Import's payee cleanup (#250): one pass over the snapshot, which inside `atomically` is the
        /// batch with the change's own writes, as `payeeReferenceCount` reads it.
        public func payeesInUse(among ids: Set<UUID>) throws -> Set<UUID> {
            try load().payeesInUse(among: ids)
        }

        public func deletePayees(ids: [UUID]) throws {
            try mutate { try LedgerBook.deletingPayees(ids: ids, in: $0, now: now()) }
        }
    }
#endif
