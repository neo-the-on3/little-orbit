#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain

    /// Edits that must find their record still stored (#264): an Edit form's save never adds back a record that
    /// was deleted while it was open.
    extension SwiftDataLedgerRepository {
        public func updateTransaction(_ transaction: Transaction) throws {
            try mutate { try LedgerBook.updatingTransaction(transaction, in: $0, now: now()) }
        }

        public var revision: UInt64? { writes }

        /// The ledger in memory, as `load()` reads it, so attachments come without their bytes (#285).
        public func batchBase() throws -> LedgerBatchBase {
            LedgerBatchBase(snapshot: try load(), revision: writes, now: now())
        }

        /// The same write as any edit: `mutate`, so inside `atomically` it joins the change's one save, and the
        /// incremental write checks it (`LedgerWriteValidation`) and saves only what differs (#285).
        public func writeBatch(_ snapshot: LedgerSnapshot) throws {
            try mutate { _ in snapshot }
        }
    }
#endif
