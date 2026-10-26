#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// #265, Tester2's 67–84 s Undo Import: an account, payee, category or tag can hold thousands of transactions
    /// in its to-many link, and SwiftData updates that link for each transaction whose to-one link to it is set,
    /// or whose delete's nullify rule takes it out, so a write of n records into a ledger of N costs about n × N.
    /// Large inserts and edits: each parent's to-many link changes in one assignment (`TransactionParentLinkPlan`).
    extension SwiftDataLedgerRepository {
        /// Links the plan's transactions from their parents, one assignment per account, payee, category and tag
        /// whose link changes, which sets the same to-one links `linkWritten` would set per transaction. Every
        /// parent first drops the transactions leaving it, then the new parents take them, so no to-one change
        /// has an old parent left to update.
        func linkFromParents(_ plan: TransactionParentLinkPlan, in index: SwiftDataStoredLedger) {
            for adding in [false, true] {
                relink(plan.changes(in: .account), adding, in: index, parents: index.accounts, \.transactions)
                relink(
                    plan.changes(in: .transferAccount),
                    adding,
                    in: index,
                    parents: index.accounts,
                    \.incomingTransfers,
                )
                relink(plan.changes(in: .category), adding, in: index, parents: index.categories, \.transactions)
                relink(plan.changes(in: .payee), adding, in: index, parents: index.payees, \.transactions)
                relink(plan.changes(in: .tag), adding, in: index, parents: index.tags, \.transactions)
            }
        }

        private func relink<Parent>(
            _ changes: [(parent: UUID, change: TransactionParentLinkPlan.Change)],
            _ adding: Bool,
            in index: SwiftDataStoredLedger,
            parents: [UUID: Parent],
            _ link: ReferenceWritableKeyPath<Parent, [LittleOrbitSchemaV1.TransactionRecord]?>,
        ) {
            for (id, change) in changes {
                guard let parent = parents[id], !(adding ? change.added.isEmpty : change.removed.isEmpty) else {
                    continue
                }
                let children = parent[keyPath: link] ?? []
                parent[keyPath: link] =
                    adding
                    ? children + change.added.compactMap { index.transactions[$0] }
                    : children.filter { !change.removed.contains($0.id) }
            }
        }
    }
#endif
