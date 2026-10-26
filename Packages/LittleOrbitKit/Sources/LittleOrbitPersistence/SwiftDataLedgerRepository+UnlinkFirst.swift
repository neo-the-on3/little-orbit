#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// #265, Tester2's 67–84 s Undo Import: an account, payee, category or tag can hold thousands of transactions
    /// in its to-many link, and SwiftData updates that link for each transaction whose to-one link to it is set,
    /// or whose delete's nullify rule takes it out, so a write of n records into a ledger of N costs about n × N.
    /// Large deletes, path (F) `LedgerDeletePath.unlinkFirst`: every parent drops its deleted children in one
    /// assignment, then each record is deleted with nothing left to nullify. Removing this path is this file, its
    /// enum case and its switch line in `removeDeleted`.
    extension SwiftDataLedgerRepository {
        /// Takes the deleted transactions, splits and payees out of the large to-many links that hold them, one
        /// assignment per parent, so their deletes have nothing left to nullify there (`LedgerDeletePath.unlinkFirst`).
        /// The links come from the ledger as stored, which is what the records hold.
        func unlinkDeleted(_ changes: LedgerWriteSet, in index: SwiftDataStoredLedger) {
            let gone = changes.transactions.deleted
            if !gone.isEmpty {
                let removed = index.snapshot.transactions.filter { gone.contains($0.id) }
                drop(gone, from: Set(removed.compactMap(\.accountID)), in: index.accounts, \.transactions)
                drop(gone, from: Set(removed.compactMap(\.transferAccountID)), in: index.accounts, \.incomingTransfers)
                drop(gone, from: Set(removed.compactMap(\.categoryID)), in: index.categories, \.transactions)
                drop(gone, from: Set(removed.compactMap(\.payeeID)), in: index.payees, \.transactions)
                drop(gone, from: Set(removed.flatMap(\.tagIDs)), in: index.tags, \.transactions)
            }
            let goneSplits = changes.splits.deleted
            if !goneSplits.isEmpty {
                let removed = index.snapshot.splits.filter { goneSplits.contains($0.id) }
                drop(goneSplits, from: Set(removed.compactMap(\.categoryID)), in: index.categories, \.splits)
            }
            let gonePayees = changes.payees.deleted
            if !gonePayees.isEmpty {
                let removed = index.snapshot.payees.filter { gonePayees.contains($0.id) }
                drop(
                    gonePayees,
                    from: Set(removed.compactMap(\.defaultCategoryID)),
                    in: index.categories,
                    \.defaultPayees,
                )
            }
        }

        private func drop<Parent, Child: IdentifiedLedgerRecord>(
            _ ids: Set<UUID>,
            from parentIDs: Set<UUID>,
            in parents: [UUID: Parent],
            _ link: ReferenceWritableKeyPath<Parent, [Child]?>,
        ) {
            for id in parentIDs {
                if let parent = parents[id] {
                    parent[keyPath: link] = parent[keyPath: link]?.filter { !ids.contains($0.recordID) }
                }
            }
        }
    }
#endif
