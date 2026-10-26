import Foundation
import LittleOrbitDomain

/// A record that lives inside another value: a budget's limit or a scheduled item's occurrence, with the id of
/// the budget or item it belongs to (#235).
struct OwnedRecord<Value: Identifiable & Hashable>: Identifiable, Hashable where Value.ID == UUID {
    var value: Value
    var ownerID: UUID

    var id: UUID { value.id }
}

/// One record type's part of a write: the values to insert or update, and the ids to delete (#235).
struct RecordChanges<Value: Identifiable & Hashable>: Equatable where Value.ID == UUID {
    var upserted: [Value] = []
    var deleted: Set<UUID> = []

    var isEmpty: Bool { upserted.isEmpty && deleted.isEmpty }
    var upsertedIDs: Set<UUID> { Set(upserted.map(\.id)) }
}

/// What a write changes between the ledger as stored and the ledger to store (#235), so the SwiftData store
/// writes only the records that differ instead of rewriting every one. A value is written again when it
/// differs, or when what it's stored with changed: a transaction or scheduled item whose account's currency
/// changed or went, a split whose transaction's currency changed, a limit whose budget's currency changed. Plain values
/// only, so it runs and is tested on every platform.
struct LedgerWriteSet: Equatable {
    /// Why this write has to go through the whole-store path, as every write did before #235.
    enum WholeStoreReason: Equatable {
        /// Two records of one type share an id, in the store or in the ledger to store.
        case duplicateIDs
        /// A value links to a record that isn't in the ledger to store. The whole-store path is what decides
        /// how such a link is stored, so it keeps doing that.
        case danglingReference
    }

    var accounts = RecordChanges<Account>()
    var categories = RecordChanges<TransactionCategory>()
    var payees = RecordChanges<Payee>()
    var tags = RecordChanges<Tag>()
    var transactions = RecordChanges<Transaction>()
    var splits = RecordChanges<TransactionSplit>()
    var attachments = RecordChanges<Attachment>()
    var budgets = RecordChanges<Budget>()
    var limits = RecordChanges<OwnedRecord<BudgetLimit>>()
    var scheduledItems = RecordChanges<ScheduledItem>()
    var occurrences = RecordChanges<OwnedRecord<ScheduledOccurrence>>()
    var wholeStoreReason: WholeStoreReason?

    var isEmpty: Bool {
        wholeStoreReason == nil && accounts.isEmpty && categories.isEmpty && payees.isEmpty && tags.isEmpty
            && transactions.isEmpty && splits.isEmpty && attachments.isEmpty && budgets.isEmpty
            && limits.isEmpty && scheduledItems.isEmpty && occurrences.isEmpty
    }

    init(from base: LedgerSnapshot, to target: LedgerSnapshot) {
        var duplicates = false
        let movedCurrencies = Self.accountsWithMovedCurrency(from: base.accounts, to: target.accounts)
        accounts = Self.changes(from: base.accounts, to: target.accounts, duplicates: &duplicates)
        categories = Self.changes(from: base.categories, to: target.categories, duplicates: &duplicates)
        payees = Self.changes(from: base.payees, to: target.payees, duplicates: &duplicates)
        tags = Self.changes(from: base.tags, to: target.tags, duplicates: &duplicates)
        transactions = Self.changes(from: base.transactions, to: target.transactions, duplicates: &duplicates) {
            Self.uses(movedCurrencies, $0.accountID, $0.transferAccountID)
        }
        let restored = Self.transactionsWithMovedCurrency(from: base, to: target, among: transactions.upsertedIDs)
        splits = Self.changes(from: base.splits, to: target.splits, duplicates: &duplicates) { split in
            split.transactionID.map(restored.contains) == true
        }
        attachments = Self.changes(from: base.attachments, to: target.attachments, duplicates: &duplicates)
        budgets = Self.changes(from: base.budgets, to: target.budgets, duplicates: &duplicates)
        let budgetCurrencies = Self.budgetsWithMovedCurrency(from: base.budgets, to: target.budgets)
        limits = Self.changes(from: Self.limits(of: base), to: Self.limits(of: target), duplicates: &duplicates) {
            budgetCurrencies.contains($0.ownerID)
        }
        scheduledItems = Self.changes(
            from: base.scheduledItems,
            to: target.scheduledItems,
            duplicates: &duplicates,
        ) {
            Self.uses(movedCurrencies, $0.accountID, $0.transferAccountID)
        }
        occurrences = Self.changes(
            from: Self.occurrences(of: base),
            to: Self.occurrences(of: target),
            duplicates: &duplicates,
        )
        if duplicates {
            wholeStoreReason = .duplicateIDs
        } else if LedgerLinks(target).hasDanglingLink(in: self, of: target) {
            wholeStoreReason = .danglingReference
        }
    }

    /// The values of `target` that are new or differ from `base`, or that `forcing` picks, and the ids of `base`
    /// that `target` no longer has. Sets `duplicates` when either side has an id twice.
    static func changes<Value: Identifiable & Hashable>(
        from base: [Value],
        to target: [Value],
        duplicates: inout Bool,
        forcing: (Value) -> Bool = { _ in false },
    ) -> RecordChanges<Value> where Value.ID == UUID {
        var stored: [UUID: Value] = [:]
        stored.reserveCapacity(base.count)
        for value in base where stored.updateValue(value, forKey: value.id) != nil {
            duplicates = true
        }
        var result = RecordChanges<Value>()
        var kept: Set<UUID> = []
        kept.reserveCapacity(target.count)
        for value in target {
            if !kept.insert(value.id).inserted {
                duplicates = true
            }
            if stored[value.id] != value || forcing(value) {
                result.upserted.append(value)
            }
        }
        for id in stored.keys where !kept.contains(id) {
            result.deleted.insert(id)
        }
        return result
    }

    static func limits(of ledger: LedgerSnapshot) -> [OwnedRecord<BudgetLimit>] {
        ledger.budgets.flatMap { budget in budget.limits.map { OwnedRecord(value: $0, ownerID: budget.id) } }
    }

    static func occurrences(of ledger: LedgerSnapshot) -> [OwnedRecord<ScheduledOccurrence>] {
        ledger.scheduledItems.flatMap { item in item.occurrences.map { OwnedRecord(value: $0, ownerID: item.id) } }
    }

    /// Accounts whose currency is different in `target`, including ones only one side has: what a transaction's
    /// or scheduled item's amounts are stored with.
    static func accountsWithMovedCurrency(from base: [Account], to target: [Account]) -> Set<UUID> {
        movedCurrencies(
            from: base.map { ($0.id, $0.currencyCode) },
            to: target.map { ($0.id, $0.currencyCode) },
        )
    }

    static func budgetsWithMovedCurrency(from base: [Budget], to target: [Budget]) -> Set<UUID> {
        movedCurrencies(
            from: base.map { ($0.id, $0.currencyCode) },
            to: target.map { ($0.id, $0.currencyCode) },
        )
    }

    /// Of the `written` transactions, the ones whose amounts are stored in another currency than before: a
    /// split's amount is stored in its transaction's account's currency, so only these transactions' splits are
    /// written again. An edit that keeps the currency, such as a move to another account in it, leaves its
    /// splits alone (#265, Bulk Edit). A transaction `base` doesn't have counts as moved.
    static func transactionsWithMovedCurrency(
        from base: LedgerSnapshot,
        to target: LedgerSnapshot,
        among written: Set<UUID>,
    ) -> Set<UUID> {
        guard !written.isEmpty else {
            return []
        }
        let before = storedCurrencies(of: base, among: written)
        let after = storedCurrencies(of: target, among: written)
        return written.filter { before[$0] != after[$0] }
    }

    /// The currency each of `ids` stores its amounts in, as the record mapping picks it.
    private static func storedCurrencies(of ledger: LedgerSnapshot, among ids: Set<UUID>) -> [UUID: String] {
        let currencies = Dictionary(
            ledger.accounts.map { ($0.id, $0.currencyCode) },
            uniquingKeysWith: { first, _ in first },
        )
        var result: [UUID: String] = [:]
        for transaction in ledger.transactions where ids.contains(transaction.id) && result[transaction.id] == nil {
            result[transaction.id] = transaction.accountID.flatMap { currencies[$0] } ?? CurrencyCode.fallback
        }
        return result
    }

    private static func movedCurrencies(from base: [(UUID, String)], to target: [(UUID, String)]) -> Set<UUID> {
        let before = Dictionary(base, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(target, uniquingKeysWith: { first, _ in first })
        var moved: Set<UUID> = []
        for (id, code) in before where after[id] != code {
            moved.insert(id)
        }
        for (id, code) in after where before[id] != code {
            moved.insert(id)
        }
        return moved
    }

    private static func uses(_ ids: Set<UUID>, _ first: UUID?, _ second: UUID?) -> Bool {
        guard !ids.isEmpty else {
            return false
        }
        return first.map(ids.contains) == true || second.map(ids.contains) == true
    }
}
