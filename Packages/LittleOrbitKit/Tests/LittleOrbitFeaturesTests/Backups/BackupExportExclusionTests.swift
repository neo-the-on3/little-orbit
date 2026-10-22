import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Observation
import Testing

/// The fake archive writer, holding each export file's write until `release()`. With `isGated` off, a write goes
/// straight through. A held write blocks a thread of the backups' own work queue (`BackupWorkExecutor`), never one
/// of the shared pool, and the suite runs in `GatedBackupSuites`, so only one write is ever held at a time.
private final class GatedArchiving: BackupArchiving, @unchecked Sendable {
    private let base = FakeBackupArchiving()
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var waiting = 0
    private var gated = true

    var isWaiting: Bool { lock.withLock { waiting > 0 } }

    var isGated: Bool {
        get { lock.withLock { gated } }
        set { lock.withLock { gated = newValue } }
    }

    func release() {
        gate.signal()
    }

    func archive(_ files: BackupSnapshotFiles) throws -> Data {
        try base.archive(files)
    }

    func archive(_ files: [BackupArchiveFile], from folder: any BackupFileReading, to url: URL) throws {
        if isGated {
            lock.withLock { waiting += 1 }
            gate.wait()
            lock.withLock { waiting -= 1 }
        }
        try base.archive(files, from: folder, to: url)
    }

    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry] {
        try base.entries(of: archive, reading: reading)
    }
}

/// Set once by an observation's change handler, which may run off the main actor.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() {
        lock.withLock { value = true }
    }
}

extension GatedBackupSuites {
    /// While a backup is written to its export file, Delete refuses it and cleanup keeps it, so its folder never goes
    /// mid-export (Tech Architect, non-blocking 3). Other backups are unaffected.
    @MainActor
    @Suite("Export blocks delete and prune of its backup", .serialized)
    struct BackupExportExclusionTests {
        private func wait(until condition: () -> Bool) async throws {
            await pollOnMainQueue(until: condition)
            #expect(condition())
        }

        private func dailyBackups(_ harness: BackupHarness, count: Int) async throws -> [BackupRecord] {
            var made: [BackupRecord] = []
            for day in 0..<count {
                harness.advance(86_400)
                try harness.repository.saveAccount(
                    Account(name: "Day \(day)", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 10)
                )
                if let record = try await harness.service.backUpAutomaticallyIfNeeded() {
                    made.append(record)
                }
            }
            return made
        }

        @Test("Deleting the backup being exported is refused; the export finishes; deleting it afterwards works")
        func delete() async throws {
            let archiving = GatedArchiving()
            let harness = try BackupHarness(archiving: archiving)
            let backup = try await harness.service.backUpNow()
            let export = Task { try await harness.service.exportBackup(id: backup.id, named: "a.littleorbit-backup") }
            try await wait { archiving.isWaiting }

            await #expect(throws: BackupError.exporting) { try await harness.service.deleteBackup(id: backup.id) }
            archiving.release()
            let file = try await export.value
            #expect(FileManager.default.fileExists(atPath: file.file.path))
            harness.service.discardExport(file)

            try await harness.service.deleteBackup(id: backup.id)
            #expect(try await harness.service.overview().backups.isEmpty)
        }

        @Test("Two overlapping exports of one backup: it stays locked until the second one finishes")
        func overlapping() async throws {
            let archiving = GatedArchiving()
            let harness = try BackupHarness(archiving: archiving)
            let backup = try await harness.service.backUpNow()
            let held = Task { try await harness.service.exportBackup(id: backup.id, named: "a.littleorbit-backup") }
            try await wait { archiving.isWaiting }

            // A second export of the same backup starts and finishes while the first is still writing.
            archiving.isGated = false
            let quick = try await harness.service.exportBackup(id: backup.id, named: "b.littleorbit-backup")
            #expect(FileManager.default.fileExists(atPath: quick.file.path))
            harness.service.discardExport(quick)
            await #expect(throws: BackupError.exporting) { try await harness.service.deleteBackup(id: backup.id) }
            #expect(try await harness.service.overview().backups.count == 1)

            archiving.release()
            let export = try await held.value
            #expect(FileManager.default.fileExists(atPath: export.file.path))
            harness.service.discardExport(export)
            try await harness.service.deleteBackup(id: backup.id)
            #expect(try await harness.service.overview().backups.isEmpty)
        }

        @Test("Delete is off in every window while the backup is exported, and on again when it ends (D208.1)")
        func deleteDisabledAcrossWindows() async throws {
            let archiving = GatedArchiving()
            let harness = try BackupHarness(archiving: archiving)
            let backup = try await harness.service.backUpNow()
            let other = try await harness.service.backUpNow()
            let model = harness.viewModel()
            let first = BackupsWindow(model: model)
            let second = BackupsWindow(model: model)
            await first.load()
            #expect(model.deleteEnabled(for: backup.id))

            let changed = ChangeFlag()
            withObservationTracking {
                _ = model.deleteEnabled(for: backup.id)
            } onChange: {
                changed.set()
            }
            let export = Task { try await harness.service.exportBackup(id: backup.id, named: "a.littleorbit-backup") }
            try await wait { archiving.isWaiting }
            // The window showing it is told, so SwiftUI redraws both windows' Delete.
            #expect(changed.isSet)
            #expect(model.isExporting(backup.id))
            #expect(!model.deleteEnabled(for: backup.id))
            #expect(model.deleteEnabled(for: other.id))
            for window in [first, second] {
                window.requestDelete(backup.id)
                #expect(window.deletePrompt == nil)
            }

            archiving.release()
            harness.service.discardExport(try await export.value)
            #expect(!model.isExporting(backup.id))
            #expect(model.deleteEnabled(for: backup.id))
            second.requestDelete(backup.id)
            #expect(second.deletePrompt?.id == backup.id)
        }

        @Test(
            "A confirmation already open when another window starts exporting shows Can’t Delete This Backup (D208.1)"
        )
        func openConfirmationRace() async throws {
            let archiving = GatedArchiving()
            let harness = try BackupHarness(archiving: archiving)
            let backup = try await harness.service.backUpNow()
            let model = harness.viewModel()
            let deleting = BackupsWindow(model: model)
            await deleting.load()
            deleting.requestDelete(backup.id)
            let row = try #require(deleting.deletePrompt)

            let export = Task { try await harness.service.exportBackup(id: backup.id, named: "a.littleorbit-backup") }
            try await wait { archiving.isWaiting }
            await deleting.confirmDelete(row)

            #expect(deleting.alert == .deleteWhileExporting)
            #expect(deleting.alert?.title == "Can’t Delete This Backup")
            #expect(deleting.alert?.message == "It’s being exported. Try again when the export has finished.")
            #expect(deleting.errorMessage == nil)
            #expect(try await harness.service.overview().backups.map(\.id) == [backup.id])

            // Nothing is queued: the backup is still there once the export ends.
            archiving.release()
            harness.service.discardExport(try await export.value)
            await deleting.load()
            #expect(try await harness.service.overview().backups.map(\.id) == [backup.id])
        }

        @Test("The service refuses it too, if the export starts after App Lock (D208.1)")
        func exportStartsDuringAppLock() async throws {
            let archiving = GatedArchiving()
            let harness = try BackupHarness(archiving: archiving)
            let backup = try await harness.service.backUpNow()
            let export = Task { try await harness.service.exportBackup(id: backup.id, named: "a.littleorbit-backup") }
            try await wait { archiving.isWaiting }
            #expect(BackupsViewModel.feedback(for: BackupError.exporting) == .alert(.deleteWhileExporting))
            await #expect(throws: BackupError.exporting) { try await harness.service.deleteBackup(id: backup.id) }
            archiving.release()
            harness.service.discardExport(try await export.value)
        }

        @Test("Cleanup keeps the backup being exported and prunes it next time")
        func prune() async throws {
            let archiving = GatedArchiving()
            let harness = try BackupHarness(archiving: archiving)
            let made = try await dailyBackups(harness, count: 3)
            #expect(made.count == 3)
            let oldest = made[0]
            let export = Task { try await harness.service.exportBackup(id: oldest.id, named: "a.littleorbit-backup") }
            try await wait { archiving.isWaiting }

            let lower = BackupRetention(recentAutomatic: 1, monthlyMonths: 0)
            let plan = try await harness.service.cleanupPlan(for: lower)
            #expect(Set(plan.backups.map(\.id)) == [made[1].id])
            _ = try await harness.service.apply(plan)
            #expect(Set(try await harness.service.overview().backups.map(\.id)) == [made[0].id, made[2].id])

            archiving.release()
            harness.service.discardExport(try await export.value)
            _ = try await harness.service.apply(try await harness.service.cleanupPlan(for: lower))
            #expect(try await harness.service.overview().backups.map(\.id) == [made[2].id])
        }
    }
}
