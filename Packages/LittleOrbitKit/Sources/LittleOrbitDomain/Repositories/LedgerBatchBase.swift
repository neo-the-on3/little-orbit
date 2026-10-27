import Foundation
import LittleOrbitCore

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
/// write, which blocks it, with the number of rows the write changes, so a sheet can show "Saving…" first, or
/// decide that it needn't show at all (D401, D402).
///
/// `willSaveOffMain`, when given, runs instead of `willSave` for a store that saves off the main actor
/// (`LedgerRepository.savesBatchesOffMain`, #285 B): the main actor stays free during the save, so the sheet
/// needn't be drawn before it.
public struct LedgerBatchReporter: Sendable {
    public var rowsDone: @Sendable (Int) -> Void
    public var willSave: @MainActor @Sendable (_ changedRows: Int) async -> Void
    public var willSaveOffMain: (@MainActor @Sendable (_ changedRows: Int) async -> Void)?

    public init(
        rowsDone: @escaping @Sendable (Int) -> Void = { _ in },
        willSave: @escaping @MainActor @Sendable (_ changedRows: Int) async -> Void = { _ in },
        willSaveOffMain: (@MainActor @Sendable (_ changedRows: Int) async -> Void)? = nil,
    ) {
        self.rowsDone = rowsDone
        self.willSave = willSave
        self.willSaveOffMain = willSaveOffMain
    }

    /// Just before the save: `willSaveOffMain` when the save runs off the main actor and it's given, otherwise
    /// `willSave`.
    @MainActor
    public func reportSaving(_ changedRows: Int, offMain: Bool) async {
        if offMain, let willSaveOffMain {
            await willSaveOffMain(changedRows)
        } else {
            await willSave(changedRows)
        }
    }

    /// Reports nothing.
    public static let silent = LedgerBatchReporter()
}

extension LedgerBatchBase {
    /// How many times a batch is built again on the main actor when the store moved just before its hand-off,
    /// before it gives up with `LedgerBatchStale`. Each rebuild is synchronous and hands off at once, so one is
    /// expected at most.
    static let handOffAttempts = 3

    /// Runs `build` on a detached task, off the main actor, and returns its result. Cancelling the caller cancels
    /// it, and it stops at its next progress report (`LedgerBook.updatingTransactions`).
    static func build<Result: Sendable>(
        _ build: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        let task = Task.detached(priority: .userInitiated) { try BatchTrace.interval("batch.build") { try build() } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// The store kept moving between a batch's rebuild and its hand-off (`LedgerBatchBase.handOffAttempts`); nothing
/// was written.
public struct LedgerBatchStale: Error, Equatable, Sendable {
    public init() {}
}
