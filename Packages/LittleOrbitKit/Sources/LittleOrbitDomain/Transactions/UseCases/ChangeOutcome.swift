import Foundation

/// A field of a transaction that a change can set. The stale check compares only the fields a change touched,
/// by value (D187.5); bookkeeping dates (`createdAt`, `updatedAt`, `deletedAt`) aren't fields a user changes.
public enum TransactionField: CaseIterable, Hashable, Sendable {
    case type, amount, date, timeZoneID, account, category, payee, details, note, transferAccount,
        destinationAmount, scheduledTemplate, scheduledOccurrenceDate, status, tags, refundOf, isRefund

    /// Whether `first` and `second` hold the same value in this field.
    public func matches(_ first: Transaction, _ second: Transaction) -> Bool {
        Self.accessors[self]?.matches(first, second) ?? true
    }

    /// Copies this field's value from `source` into `target`.
    public func copy(from source: Transaction, into target: inout Transaction) {
        Self.accessors[self]?.copy(source, &target)
    }

    private struct Accessor: Sendable {
        let matches: @Sendable (Transaction, Transaction) -> Bool
        let copy: @Sendable (Transaction, inout Transaction) -> Void

        static func of<Value: Equatable & Sendable>(_ field: WritableKeyPath<Transaction, Value> & Sendable) -> Self {
            Self(
                matches: { $0[keyPath: field] == $1[keyPath: field] },
                copy: { source, target in target[keyPath: field] = source[keyPath: field] },
            )
        }
    }

    private static let accessors: [Self: Accessor] = [
        .type: .of(\.type),
        .amount: .of(\.amount),
        .date: .of(\.date),
        .timeZoneID: .of(\.timeZoneID),
        .account: .of(\.accountID),
        .category: .of(\.categoryID),
        .payee: .of(\.payeeID),
        .details: .of(\.details),
        .note: .of(\.note),
        .transferAccount: .of(\.transferAccountID),
        .destinationAmount: .of(\.destinationAmount),
        .scheduledTemplate: .of(\.scheduledTemplateID),
        .scheduledOccurrenceDate: .of(\.scheduledOccurrenceDate),
        .status: .of(\.status),
        .tags: .of(\.tagIDs),
        .refundOf: .of(\.refundOfID),
        .isRefund: .of(\.isRefund),
    ]

    /// The fields that differ between two versions of a transaction.
    public static func changed(from before: Transaction, to after: Transaction) -> Set<TransactionField> {
        Set(allCases.filter { !$0.matches(before, after) })
    }
}

/// What a change left in the ledger, read right after it and kept with its undo step (D187.5). Each window
/// has its own undo history (D187.2), so another window, or something outside any window, may change the
/// same records first. Reverting compares the ledger with this, by value, and writes nothing if it differs.
public struct ChangeOutcome: Equatable, Sendable {
    /// The transactions the change left, as stored right after it.
    public var transactions: [UUID: Transaction]
    /// For each of `transactions`, the fields the change set. Only these are compared, so another window's
    /// change to a different field doesn't make the step stale.
    public var touchedFields: [UUID: Set<TransactionField>]
    /// Transactions the change deleted; they must still be gone.
    public var removedTransactionIDs: Set<UUID>
    /// Accounts reverting writes into or restores; they must still exist.
    public var accountIDs: Set<UUID>
    /// Accounts the change deleted; they must still be gone.
    public var removedAccountIDs: Set<UUID>
    /// For an account the change restored, every transaction in or out of it, so reverting never deletes a
    /// transaction another window added to it since.
    public var accountContents: [UUID: Set<UUID>]
    /// For each transaction whose split lines the change replaced, the lines it left. They must still be
    /// there, unchanged in ID, category, amount, note and order (`SplitLineValue`).
    public var splitLines: [UUID: [SplitLineValue]]

    public init(
        transactions: [UUID: Transaction] = [:],
        touchedFields: [UUID: Set<TransactionField>] = [:],
        removedTransactionIDs: Set<UUID> = [],
        accountIDs: Set<UUID> = [],
        removedAccountIDs: Set<UUID> = [],
        accountContents: [UUID: Set<UUID>] = [:],
        splitLines: [UUID: [SplitLineValue]] = [:],
    ) {
        self.transactions = transactions
        self.touchedFields = touchedFields
        self.removedTransactionIDs = removedTransactionIDs
        self.accountIDs = accountIDs
        self.removedAccountIDs = removedAccountIDs
        self.accountContents = accountContents
        self.splitLines = splitLines
    }
}

/// A split line as the stale check compares it: what a user can change, not the bookkeeping dates.
public struct SplitLineValue: Equatable, Sendable {
    public var id: UUID
    public var categoryID: UUID?
    public var amount: Decimal
    public var note: String?
    public var sortOrder: Double

    public init(_ split: TransactionSplit) {
        id = split.id
        categoryID = split.categoryID
        amount = split.amount
        note = split.note
        sortOrder = split.sortOrder
    }

    /// The live lines of a transaction, in their order.
    public static func of(_ splits: [TransactionSplit]) -> [SplitLineValue] {
        splits.filter { $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
            .map(SplitLineValue.init)
    }
}

/// Why a step can't be reverted any more (D187.5). Facts only; how to word them is up to the caller.
public enum StaleReason: Equatable, Sendable {
    /// These accounts, which reverting needs, were deleted.
    case accountDeleted([UUID])
    /// These transactions were deleted.
    case deleted([UUID])
    /// These transactions no longer hold what the change left: a touched field was changed, a deleted one is
    /// back, or an account the change restored has other transactions now.
    case changed([UUID])
    /// Some of these transactions were changed and others deleted (a bulk step, D189.2).
    case changedAndDeleted(changed: [UUID], deleted: [UUID])
}

/// The stale check's result: the ledger still holds what the change left, or it doesn't, and why.
public enum ChangeCheck: Equatable, Sendable {
    case current
    case stale(StaleReason)
}

/// What reverting a change did: reverted it, returning its inverse and what that left for the next check, or
/// found it stale and wrote nothing.
public enum RevertResult: Equatable, Sendable {
    case reverted(TransactionChange, ChangeOutcome)
    case stale(StaleReason)
}
