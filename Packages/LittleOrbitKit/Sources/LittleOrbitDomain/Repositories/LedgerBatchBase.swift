import Foundation

/// The ledger a batch is built from off the main actor (#285): the snapshot, the store's clock for the
/// timestamps it sets, and the store's revision, so the commit can tell whether anything wrote in between.
public struct LedgerBatchBase: Equatable, Sendable {
    public var snapshot: LedgerSnapshot
    public var revision: UInt64
    public var now: Date

    public init(snapshot: LedgerSnapshot, revision: UInt64, now: Date) {
        self.snapshot = snapshot
        self.revision = revision
        self.now = now
    }
}

/// How a batch reports while it runs, for a progress sheet (#285, D398.3). `rowsDone` may be called off the main
/// actor, every `LedgerBook.batchProgressStride` rows. `willSave` runs on the main actor just before the one
/// write, which blocks it, so a sheet can show "Saving…" first.
public struct LedgerBatchReporter: Sendable {
    public var rowsDone: @Sendable (Int) -> Void
    public var willSave: @MainActor @Sendable () async -> Void

    public init(
        rowsDone: @escaping @Sendable (Int) -> Void = { _ in },
        willSave: @escaping @MainActor @Sendable () async -> Void = {},
    ) {
        self.rowsDone = rowsDone
        self.willSave = willSave
    }

    /// Reports nothing.
    public static let silent = LedgerBatchReporter()
}

extension LedgerBatchBase {
    /// Runs `build` on a detached task, off the main actor, and returns its result. Cancelling the caller cancels
    /// it, and it stops at its next progress report (`LedgerBook.updatingTransactions`).
    static func build<Result: Sendable>(
        _ build: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        let task = Task.detached(priority: .userInitiated) { try build() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
