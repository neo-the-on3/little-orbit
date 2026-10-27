import Foundation
import LittleOrbitDomain

/// A batch write the SwiftData store saves on a background model actor (#285, B), as plain values: what each
/// record gets and which parents' links change, with every record named by its store identifier (SwiftData's
/// `PersistentIdentifier`, a number in tests). It's built on the main actor from the ledger in memory, after the
/// write is checked (`LedgerWriteValidation`), and crosses to the writer, which reads nothing of the main actor's.
///
/// Only the shape a Bulk Edit, its Undo and its Redo write goes this way: existing transactions changed, payees
/// added, changed or removed, nothing else. Any other write is `nil` and goes through the main-actor write.
/// Plain values only, so it runs and is tested on every platform.
struct BackgroundBatchPlan<RecordID: Hashable & Sendable>: Sendable {
    /// The record types a plan names.
    enum Kind: Hashable, Sendable {
        case account
        case category
        case payee
        case tag
        case transaction
    }

    /// A parent whose link changes: a stored record, or a payee this write adds, by its ledger id.
    enum Parent: Hashable, Sendable {
        case stored(RecordID)
        case createdPayee(UUID)
    }

    /// A stored transaction's new value, with how it was stored before and the currencies its amounts are stored
    /// in, as `writeFields` works them out.
    struct TransactionWrite: Sendable {
        var record: RecordID
        var value: Transaction
        var stored: Transaction
        var sourceCurrency: String
        var destinationCurrency: String?
    }

    /// A payee's new value; `record` is `nil` for one this write adds.
    struct PayeeWrite: Sendable {
        var record: RecordID?
        var value: Payee
        var defaultCategory: RecordID?
    }

    /// A payee this write removes.
    struct PayeeRemoval: Sendable {
        var id: UUID
        var record: RecordID
    }

    /// One parent's to-many link losing or gaining transactions, as `linkFromParents` assigns it (#265).
    struct Relink: Sendable {
        var link: TransactionParentLinkPlan.Link
        var parent: Parent
        var removed: [RecordID]
        var added: [RecordID]
    }

    var transactions: [TransactionWrite] = []
    var payees: [PayeeWrite] = []
    var removedPayees: [PayeeRemoval] = []
    /// Every removal first, then every addition, each in `TransactionParentLinkPlan.Link` order.
    var relinks: [Relink] = []
    /// For tests: the writer fails after changing its records and before its one save.
    var failsBeforeSave = false

    /// The plan for `changes`, the write from `stored` to `target`, or `nil` when it isn't a write this path takes
    /// or a record it names has no identifier. `recordID` finds a stored record's identifier by its ledger id.
    static func make(
        _ changes: LedgerWriteSet,
        from stored: LedgerSnapshot,
        to target: LedgerSnapshot,
        recordID: (Kind, UUID) -> RecordID?,
    ) -> BackgroundBatchPlan? {
        guard changes.wholeStoreReason == nil, changes.accounts.isEmpty, changes.categories.isEmpty,
            changes.tags.isEmpty, changes.splits.isEmpty, changes.attachments.isEmpty, changes.budgets.isEmpty,
            changes.limits.isEmpty, changes.scheduledItems.isEmpty, changes.occurrences.isEmpty,
            changes.transactions.deleted.isEmpty, !changes.isEmpty
        else {
            return nil
        }
        var plan = BackgroundBatchPlan()
        let upsertedIDs = changes.transactions.upsertedIDs
        var before: [UUID: Transaction] = [:]
        before.reserveCapacity(upsertedIDs.count)
        for transaction in stored.transactions
        where upsertedIDs.contains(transaction.id) && before[transaction.id] == nil {
            before[transaction.id] = transaction
        }
        guard plan.addTransactions(changes.transactions.upserted, before: before, in: target, recordID: recordID),
            let created = plan.addPayees(changes.payees, storedIDs: Set(stored.payees.map(\.id)), recordID: recordID),
            plan.addRelinks(
                TransactionParentLinkPlan(writing: changes.transactions.upserted, over: before),
                created: created,
                recordID: recordID,
            )
        else {
            return nil
        }
        return plan
    }

    /// The ledger the store holds once the plan is saved: `target` with each written transaction and payee as the
    /// writer read it back from its record, so reads see exactly what a fresh load would.
    static func installed(
        _ target: LedgerSnapshot,
        readBack receipt: BackgroundBatchReceipt<RecordID>,
    ) -> LedgerSnapshot {
        var snapshot = target
        snapshot.transactions = replacing(snapshot.transactions, with: receipt.transactions)
        snapshot.payees = replacing(snapshot.payees, with: receipt.payees)
        return snapshot
    }

    private static func replacing<Value: Identifiable>(_ values: [Value], with readBack: [Value]) -> [Value]
    where Value.ID == UUID {
        guard !readBack.isEmpty else {
            return values
        }
        var byID: [UUID: Value] = [:]
        byID.reserveCapacity(readBack.count)
        for value in readBack {
            byID[value.id] = value
        }
        return values.map { byID[$0.id] ?? $0 }
    }

    private mutating func addTransactions(
        _ upserted: [Transaction],
        before: [UUID: Transaction],
        in target: LedgerSnapshot,
        recordID: (Kind, UUID) -> RecordID?,
    ) -> Bool {
        let currencies = Dictionary(
            target.accounts.map { ($0.id, $0.currencyCode) },
            uniquingKeysWith: { first, _ in first },
        )
        transactions.reserveCapacity(upserted.count)
        for value in upserted {
            // A new transaction has no record yet: such a write goes through the main actor.
            guard let stored = before[value.id], let record = recordID(.transaction, value.id) else {
                return false
            }
            transactions.append(
                TransactionWrite(
                    record: record,
                    value: value,
                    stored: stored,
                    sourceCurrency: value.accountID.flatMap { currencies[$0] } ?? CurrencyCode.fallback,
                    destinationCurrency: value.transferAccountID.flatMap { currencies[$0] },
                )
            )
        }
        return true
    }

    /// Adds the payee writes and removals; returns the ids of the payees the write adds, or `nil` when a record
    /// it names has no identifier.
    private mutating func addPayees(
        _ changes: RecordChanges<Payee>,
        storedIDs: Set<UUID>,
        recordID: (Kind, UUID) -> RecordID?,
    ) -> Set<UUID>? {
        var created: Set<UUID> = []
        for payee in changes.upserted {
            var record: RecordID?
            if storedIDs.contains(payee.id) {
                guard let found = recordID(.payee, payee.id) else {
                    return nil
                }
                record = found
            } else {
                created.insert(payee.id)
            }
            var category: RecordID?
            if let categoryID = payee.defaultCategoryID {
                guard let found = recordID(.category, categoryID) else {
                    return nil
                }
                category = found
            }
            payees.append(PayeeWrite(record: record, value: payee, defaultCategory: category))
        }
        for id in Self.ordered(changes.deleted) {
            guard let record = recordID(.payee, id) else {
                return nil
            }
            removedPayees.append(PayeeRemoval(id: id, record: record))
        }
        return created
    }

    private mutating func addRelinks(
        _ links: TransactionParentLinkPlan,
        created: Set<UUID>,
        recordID: (Kind, UUID) -> RecordID?,
    ) -> Bool {
        for adding in [false, true] {
            for link in TransactionParentLinkPlan.Link.allCases {
                for (parentID, change) in links.changes(in: link) {
                    let ids = adding ? change.added : Self.ordered(change.removed)
                    guard !ids.isEmpty else {
                        continue
                    }
                    let parent: Parent
                    if link == .payee, created.contains(parentID) {
                        parent = .createdPayee(parentID)
                    } else if let found = recordID(Self.kind(of: link), parentID) {
                        parent = .stored(found)
                    } else {
                        return false
                    }
                    let children = ids.compactMap { recordID(.transaction, $0) }
                    guard children.count == ids.count else {
                        return false
                    }
                    relinks.append(
                        Relink(
                            link: link,
                            parent: parent,
                            removed: adding ? [] : children,
                            added: adding ? children : [],
                        )
                    )
                }
            }
        }
        return true
    }

    private static func kind(of link: TransactionParentLinkPlan.Link) -> Kind {
        switch link {
        case .account, .transferAccount: .account
        case .category: .category
        case .payee: .payee
        case .tag: .tag
        }
    }

    private static func ordered(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted { $0.uuidString < $1.uuidString }
    }
}

/// What the background writer hands back after its one save (#285, B): each written transaction and payee as read
/// back from its record, and the identifiers of the payees it added, so the main actor can install the result
/// without fetching the store again.
struct BackgroundBatchReceipt<RecordID: Hashable & Sendable>: Sendable {
    var transactions: [Transaction] = []
    var payees: [Payee] = []
    var createdPayees: [UUID: RecordID] = [:]
}
