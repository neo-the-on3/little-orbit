#if canImport(SwiftData) && os(macOS)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// Where an incremental write's time goes, from the repository's test hooks: each mark is the time since
    /// `begin()`. The first includes the use case and `LedgerWriteSet`; "saved" ends the `save()`; the rest of
    /// the write's total is the in-memory ledger's reread (#265, why Redo took twice Undo's time).
    @MainActor
    final class WritePhases {
        private let clock = ContinuousClock()
        private let repository: SwiftDataLedgerRepository
        private var start: ContinuousClock.Instant
        private var marks: [String] = []

        init(on repository: SwiftDataLedgerRepository) {
            self.repository = repository
            start = clock.now
            repository.afterStep = { [weak self] step in self?.mark("\(step)") }
            repository.beforeSave = { [weak self] _ in self?.mark("beforeSave") }
            repository.afterSave = { [weak self] in self?.mark("saved") }
        }

        func begin() {
            start = clock.now
            marks = []
        }

        func stop() {
            repository.afterStep = nil
            repository.beforeSave = nil
            repository.afterSave = nil
        }

        var summary: String {
            (marks + ["total \(clock.now - start)"]).joined(separator: ", ")
        }

        private func mark(_ name: String) {
            marks.append("\(name) \(clock.now - start)")
        }
    }

    /// #270's Bulk Edit (Tester2, comment 6429205207: 65–76 s on main for 3,334 rows of the 10,000) as the
    /// repository sees it: one ledger change that edits the account, category, payee, amount and note of 3,334
    /// transactions. Only those transactions and the parents whose links they change are written.
    extension SwiftDataWriteTimingTests {
        static let bulkEditCount = 3334

        /// Every third transaction edited: the other account, the next category and payee, the amount plus one and
        /// a note. Returns the ids it edited.
        static func bulkEdited(_ snapshot: LedgerSnapshot) -> (LedgerSnapshot, Set<UUID>) {
            func next(_ ids: [UUID], after id: UUID?) -> UUID? {
                guard let index = ids.firstIndex(where: { $0 == id }) else {
                    return ids.first
                }
                return ids[(index + 1) % ids.count]
            }
            let accounts = snapshot.accounts.map(\.id)
            let categories = snapshot.categories.map(\.id)
            let payees = snapshot.payees.map(\.id)
            var edited = snapshot
            var ids = Set<UUID>()
            for index in edited.transactions.indices where index.isMultiple(of: 3) {
                var transaction = edited.transactions[index]
                transaction.accountID = next(accounts, after: transaction.accountID)
                transaction.categoryID = next(categories, after: transaction.categoryID)
                transaction.payeeID = next(payees, after: transaction.payeeID)
                transaction.amount += 1
                transaction.note = "Bulk edit \(index)"
                edited.transactions[index] = transaction
                ids.insert(transaction.id)
            }
            return (edited, ids)
        }

        struct BulkEditTiming {
            let edit: Duration
            let undo: Duration
            let redo: Duration
            let phases: String
        }

        /// The Bulk Edit, its Undo (the rows put back as they were) and its Redo, each one write, timed.
        static func bulkEditAndUndo(on repository: SwiftDataLedgerRepository) throws -> BulkEditTiming {
            let original = try repository.load()
            let (edited, ids) = bulkEdited(original)
            #expect(ids.count == bulkEditCount)
            let clock = ContinuousClock()
            let phases = WritePhases(on: repository)
            defer { phases.stop() }
            let edit = try clock.measure { try repository.mutate { _ in edited } }
            let editPhases = phases.summary
            try expectTransactions(on: repository, as: edited, ids)
            phases.begin()
            let undo = try clock.measure { try repository.mutate { _ in original } }
            let undoPhases = phases.summary
            try expectTransactions(on: repository, as: original, ids)
            phases.begin()
            let redo = try clock.measure { try repository.mutate { _ in edited } }
            let redoPhases = phases.summary
            try expectTransactions(on: repository, as: edited, ids)
            return BulkEditTiming(
                edit: edit,
                undo: undo,
                redo: redo,
                phases: "edit [\(editPhases)], undo [\(undoPhases)], redo [\(redoPhases)]",
            )
        }

        /// The edited transactions read back as `expected` has them, and the ledger still has all 10,000.
        static func expectTransactions(
            on repository: SwiftDataLedgerRepository,
            as expected: LedgerSnapshot,
            _ ids: Set<UUID>,
        ) throws {
            let read = try repository.transactions()
            #expect(read.count == existing)
            let wanted = Set(expected.transactions.filter { ids.contains($0.id) })
            #expect(Set(read.filter { ids.contains($0.id) }) == wanted)
        }

        @Test("A Bulk Edit of 3,334 rows in a ledger of 10,000, undone and redone (#270)")
        func bulkEdit() throws {
            let (repository, folder) = try Self.reopenCopy()
            defer { try? FileManager.default.removeItem(at: folder) }
            let timing = try Self.bulkEditAndUndo(on: repository)
            print(
                "SwiftData timing: bulk edit of \(Self.bulkEditCount) in \(Self.existing): "
                    + "edit \(timing.edit), undo \(timing.undo), redo \(timing.redo)"
            )
            print("SwiftData timing phases: bulk edit: \(timing.phases)")
            try TimingScale.expect("bulk edit: edit", timing.edit, under: .seconds(1))
            try TimingScale.expect("bulk edit: undo", timing.undo, under: .seconds(1))
            try TimingScale.expect("bulk edit: redo", timing.redo, under: .seconds(1))
        }

        /// Main's whole-store write re-saves every record (Tester2: 65–76 s for this edit). The incremental write
        /// changes only the edited transactions and the accounts, categories and payees whose links they leave or
        /// join, and inserts nothing, as the context has them just before the one `save()`.
        @Test("A Bulk Edit changes only the edited transactions and their parents (#270)")
        func bulkEditDirtiesOnlyEditedRows() throws {
            let (repository, folder) = try Self.reopenCopy()
            defer { try? FileManager.default.removeItem(at: folder) }
            let (edited, ids) = Self.bulkEdited(try repository.load())
            var inserted = -1
            var changedTransactions = Set<UUID>()
            var changedParents = 0
            var changedOthers: [String] = []
            repository.beforeSave = { _ in
                inserted = repository.context.insertedModelsArray.count
                for model in repository.context.changedModelsArray {
                    if let transaction = model as? LittleOrbitSchemaV1.TransactionRecord {
                        changedTransactions.insert(transaction.id)
                    } else if model is LittleOrbitSchemaV1.AccountRecord || model is LittleOrbitSchemaV1.CategoryRecord
                        || model is LittleOrbitSchemaV1.PayeeRecord
                    {
                        changedParents += 1
                    } else {
                        changedOthers.append(String(describing: type(of: model)))
                    }
                }
            }
            try repository.mutate { _ in edited }
            repository.beforeSave = nil
            #expect(inserted == 0)
            #expect(changedTransactions == ids)
            #expect(changedOthers.isEmpty)
            #expect(changedParents <= 2 + 20 + 300)
            try Self.expectTransactions(on: repository, as: edited, ids)
        }

        static func ladderBulkEdit(_ path: Path) throws {
            let (repository, folder) = try reopenCopy()
            defer { try? FileManager.default.removeItem(at: folder) }
            repository.deletePathOverride = path.delete
            repository.linksFromParentsOverride = path.linksFromParents
            let timing = try bulkEditAndUndo(on: repository)
            print(
                "SwiftData ladder: \(path) bulk edit=\(bulkEditCount) in=\(existing): "
                    + "edit \(timing.edit), undo \(timing.undo), redo \(timing.redo)"
            )
            print("SwiftData ladder phases: \(path) bulk edit: \(timing.phases)")
        }

        struct InjectedFailure: Error {}

        /// A write that fails drops the context and the in-memory ledger (`discardChanges(after:)`), so the next
        /// read loads all 10,000 again: its time, after a one-row save that fails at its `save()`.
        static func ladderReloadAfterFailedWrite() throws {
            let (repository, folder) = try reopenCopy()
            defer { try? FileManager.default.removeItem(at: folder) }
            let account = try #require(try repository.accounts().first)
            repository.beforeSave = { _ in throw InjectedFailure() }
            #expect(throws: InjectedFailure.self) {
                try repository.saveTransaction(
                    Transaction(amount: 250, timeZoneID: zone.identifier, accountID: account.id)
                )
            }
            repository.beforeSave = nil
            var count = 0
            let reload = try ContinuousClock().measure { count = try repository.transactions().count }
            #expect(count == existing)
            print("SwiftData ladder: full read of \(existing) after a failed write: \(reload)")
        }
    }
#endif
