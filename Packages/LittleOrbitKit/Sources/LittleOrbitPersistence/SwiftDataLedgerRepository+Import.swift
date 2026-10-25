#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain

    /// CSV import (#30): a batch of transactions saved or removed in one pass, through the same `LedgerBook`
    /// rules as saving or deleting each.
    extension SwiftDataLedgerRepository {
        public func saveNewTransactions(_ transactions: [Transaction]) throws {
            try mutate { try LedgerBook.savingNewTransactions(transactions, in: $0, now: now()) }
        }

        public func deleteTransactions(ids: [UUID]) throws {
            try mutate { try LedgerBook.deletingTransactions(ids: ids, in: $0, now: now()) }
        }
    }
#endif
