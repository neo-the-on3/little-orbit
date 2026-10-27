import Foundation

/// Bulk Edit's Apply was refused because these selected transactions were deleted after the sheet opened, say in
/// another window. Nothing was written (D393.1).
public struct BulkEditSelectionDeleted: Error, Equatable, Sendable {
    /// The selected transactions that are no longer stored.
    public var ids: Set<UUID>

    public init(ids: Set<UUID>) {
        self.ids = ids
    }
}

/// Bulk Edit's Apply, run as a batch, was refused because the data changed while it was built and the change no
/// longer passes the shared rules on the data as it is now. Nothing was written (D399).
public struct BulkEditDataChanged: Error, Equatable, Sendable {
    public init() {}
}

/// One Apply of the macOS "Edit N Transactions" sheet: its ticked fields for the transactions it opened with.
public struct BulkEditRequest: Equatable, Sendable {
    /// The selected transactions as the sheet read them.
    public var selection: [Transaction]
    /// The ticked fields. A ticked Payee (`payeeID` not `nil`) uses `payeeName`, resolved on apply.
    public var changes: BulkEditChanges
    /// The typed payee name, used only when Payee is ticked. A blank one clears the payee.
    public var payeeName: String
    public var accounts: [Account]
    /// The zone a changed date is stored in.
    public var timeZoneID: String
    /// When a new payee is created.
    public var now: Date

    public init(
        selection: [Transaction],
        changes: BulkEditChanges,
        payeeName: String,
        accounts: [Account],
        timeZoneID: String,
        now: Date,
    ) {
        self.selection = selection
        self.changes = changes
        self.payeeName = payeeName
        self.accounts = accounts
        self.timeZoneID = timeZoneID
        self.now = now
    }
}

@MainActor
public protocol ApplyBulkEditUseCase {
    /// Applies the request's ticked fields as `BulkEditRules.apply` does, and saves the transactions that change
    /// with any payee it creates, all or none. Returns the change to register for Undo; `.replaced([])` when no
    /// transaction changes.
    ///
    /// All or nothing (#268, D393.1): if any selected transaction is no longer stored, it throws
    /// `BulkEditSelectionDeleted` naming them and writes nothing. No transaction is changed or added back, and no
    /// payee is created. The check and the writes are one store change, so a delete can't land between them.
    ///
    /// Only the ticked fields change, on the rows as stored at Apply time (D395): a field another window changed
    /// since the sheet opened keeps that value. Undo restores only the ticked fields, and Redo reapplies them.
    func apply(_ request: BulkEditRequest) throws -> TransactionChange
    /// `apply(_:)` with the rows checked off the main actor, reporting as it goes, then one write on the main
    /// actor (#285, D398). Cancelled before that write, it writes nothing and throws `CancellationError`.
    func apply(_ request: BulkEditRequest, reporting reporter: LedgerBatchReporter) async throws -> TransactionChange
}

extension ApplyBulkEditUseCase {
    /// `apply(_:)` on the main actor, for a use case without a batch path.
    public func apply(
        _ request: BulkEditRequest,
        reporting _: LedgerBatchReporter,
    ) async throws -> TransactionChange {
        try apply(request)
    }
}

@MainActor
public struct DefaultApplyBulkEditUseCase: ApplyBulkEditUseCase {
    let repository: any LedgerRepository
    private let save: DefaultSaveTransactionsUseCase

    public init(repository: any LedgerRepository) {
        self.repository = repository
        save = DefaultSaveTransactionsUseCase(repository: repository)
    }

    /// The same steps as `apply(_:reporting:)`, all on the main actor in one change (#285). A store without the
    /// batch path saves the rows one by one instead.
    public func apply(_ request: BulkEditRequest) throws -> TransactionChange {
        guard repository.revision == nil else {
            return try commit(nil, for: request)
        }
        return try repository.atomically {
            // Every selected row, changed by this edit or not: the sheet's count and its rows must still be stored.
            let stored = Dictionary(
                try repository.transactions().filter { $0.deletedAt == nil }.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first },
            )
            let deleted = Set(request.selection.map(\.id).filter { stored[$0] == nil })
            guard deleted.isEmpty else {
                throw BulkEditSelectionDeleted(ids: deleted)
            }
            // The ticked fields go onto the rows as stored now, not as the sheet read them, so fields that weren't
            // ticked keep what another window gave them (D395). The save then records these rows as the earlier
            // versions, so Undo and Redo touch only the fields that changed (D187.5).
            let current = request.selection.compactMap { stored[$0.id] }
            var changes = request.changes
            var created: [Payee] = []
            // Payee skips transfers (D114), so a transfers-only selection never creates a typed payee.
            if changes.payeeID != nil, current.contains(where: { $0.type != .transfer }) {
                let resolved = try save.resolvePayee(named: request.payeeName, createdAt: request.now)
                changes.payeeID = .some(resolved?.payee.id)
                created = resolved.flatMap { $0.isNew ? [$0.payee] : nil } ?? []
            }
            let updated = BulkEditRules.apply(
                changes,
                to: current,
                accounts: request.accounts,
                timeZoneID: request.timeZoneID,
            )
            let changed = zip(current, updated).filter { $0 != $1 }.map(\.1)
            if changed.isEmpty {
                return .replaced([])
            }
            // A payee this edit created goes with it on Undo, unless something else uses it by then (D191.4).
            return try save.save(changed, creating: created)
        }
    }
}
