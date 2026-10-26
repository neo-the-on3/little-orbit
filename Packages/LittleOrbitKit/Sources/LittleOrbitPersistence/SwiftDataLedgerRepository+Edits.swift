#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain

    /// Edits that must find their record still stored (#264): an Edit form's save never adds back a record that
    /// was deleted while it was open.
    extension SwiftDataLedgerRepository {
        public func updateTransaction(_ transaction: Transaction) throws {
            try mutate { try LedgerBook.updatingTransaction(transaction, in: $0, now: now()) }
        }
    }
#endif
