import Foundation
import LittleOrbitDomain
import Observation

/// An exported backup's file, with its suggested name, for `fileExporter`. The file is in the staging folder until
/// the save panel or share sheet closes (B2).
public struct BackupExportFile: Equatable, Sendable {
    public var export: BackupExport
    /// `little-orbit YYYY-MM-DD HHmm[ n].littleorbit-backup`.
    public var fileName: String

    public init(export: BackupExport, fileName: String) {
        self.export = export
        self.fileName = fileName
    }

    public var url: URL {
        export.file
    }
}

/// The Export sheet for one backup, in order: its summary, the note that the file isn't encrypted, then Cancel
/// and Export (R1, S64, D182.4, D186; UI Designer, frames 277:4581 macOS and 277:4915 iOS).
public struct BackupExportPrompt: Identifiable, Equatable, Sendable {
    public var id: UUID { record.id }
    public var record: BackupRecord
    /// "Today, 9:12 AM", for the iOS Backup cell.
    public var dateText: String
    /// "Backup from Yesterday, 8:47 PM · Manual · 5 accounts · 118 transactions", plus attachments when there
    /// are any (S64, S76).
    public var summary: String
}

/// 'Delete 4 Backups?' after N or M was lowered (D195.5, L12). Nothing is deleted until it's confirmed.
///
/// It's transient UI state, so the window that showed it keeps it, never the shared view model: another window
/// still shows the saved N and M, and its own alerts (Tech Architect). See `BackupsViewModel.proposeRetention`.
public struct BackupPrunePrompt: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var plan: BackupCleanupPlan
    /// The N and M to go back to on Cancel (L13).
    public var previous: BackupRetention
    public var title: String
    public var message: String
    /// The destructive button, 'Delete 4 Backups'. It isn't the default button (L12).
    public var confirmTitle: String
}

/// The restore warning, with the checked backup it would restore.
public struct BackupRestorePrompt: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var message: String
    /// Where the checked backup is: read again, and checked again, only when Restore is tapped. The warning holds
    /// no part of the backup but its manifest (B1).
    public var source: BackupSource
    public var manifest: BackupManifest
}

/// What a finished restore tells the window that ran it.
public struct BackupRestoreOutcome: Equatable, Sendable {
    /// iOS: the toast "Backup restored · Before restore backup saved".
    public var toast: String
    /// macOS: the inline line in the Backups tab (frame 169:5253).
    public var restoredMessage: String
}

/// How a window shows a failed action: one of the two backup alerts, the generic error, or nothing (the failure
/// line already says it, or another backup was running).
public enum BackupFeedback: Equatable, Sendable {
    case alert(BackupAlert)
    case error(String)
    case none
}

/// Settings > Backups on iOS and the Backups settings tab on macOS (#40): the data every window shows.
///
/// It's shared by every window, so it holds data and the state of a running backup or restore only. Prompts,
/// alerts, errors, the export file and the restore toast are transient UI state: each window keeps its own in a
/// `BackupsWindow` (Tech Architect; the same as #87's B3 `AccountDeleteConfirmation`). The actions here return
/// what a window should show, or throw, and never present anything themselves.
///
/// Depends only on the backup use-case protocols. Restore, Export and Delete ask the App Lock hook first
/// (`AppAuthenticationUseCase`, D63); Delete confirms before that (S51). While a backup or restore runs, the other
/// actions are disabled in every window, never queued (D118.5).
@MainActor
@Observable
public final class BackupsViewModel {
    public private(set) var rows: [BackupRowModel] = []
    public private(set) var records: [BackupRecord] = []
    /// "Last backup: Today, 9:12 AM." with the retention rule, or only the rule when there are no backups.
    public private(set) var lastBackupText: String?
    public private(set) var failureMessage: String?
    public private(set) var isBackingUp = false
    /// Non-nil while a restore runs. Every window's actions are off; the window that started it shows the
    /// progress screen, with no Cancel (D116.2).
    public private(set) var restoreStep: BackupRestoreStep?

    public private(set) var presentation: BackupPresentation
    private let useCases: BackupUseCases
    private let now: @MainActor () -> Date
    private let announce: @MainActor (String) -> Void
    /// The background backup that's running, if any.
    @ObservationIgnored private var backgroundRun: BackgroundBackupRun?
    @ObservationIgnored private var automaticRun: Task<Void, Never>?

    /// `announce` posts a VoiceOver announcement; the App passes `AccessibilityNotification.Announcement`.
    public init(
        useCases: BackupUseCases,
        presentation: BackupPresentation,
        now: @escaping @MainActor () -> Date = { Date() },
        announce: @escaping @MainActor (String) -> Void = { _ in },
    ) {
        self.useCases = useCases
        self.presentation = presentation
        self.now = now
        self.announce = announce
    }

    /// The Backups folder couldn't be read: the list shows "Couldn’t Load Backups" with Try Again instead of its
    /// rows, never an alert (D211.5).
    public private(set) var isLoadFailed = false

    public var isEmpty: Bool {
        rows.isEmpty
    }

    /// Restore, Export, Delete and Back Up Now are off while a backup or restore runs (D118.5).
    public var actionsEnabled: Bool {
        !isBackingUp && restoreStep == nil
    }

    /// The saved N and M (D195.4). A window waiting for its 'Delete N Backups?' answer shows the proposed values
    /// itself.
    public var retention: BackupRetention {
        presentation.retention
    }

    /// The footer under Keep (L11), for the saved N and M.
    public var keepFooter: String {
        presentation.keepFooter
    }

    /// Both steppers are off while a backup or restore runs (L14, D118.5). A window also turns its own off while
    /// its 'Delete N Backups?' alert waits.
    public var retentionEnabled: Bool {
        actionsEnabled
    }

    /// The Delete footnote on a backup's detail (D196.1, L25). The same for every kind.
    public func deleteFootnote(for id: UUID) -> String {
        presentation.deleteFootnote(useCases.authentication.unlockMethod())
    }

    /// The restore progress bar's value.
    public var restoreFraction: Double {
        restoreStep.map(BackupPresentation.fraction) ?? 0
    }

    /// Whether "Current data saved as a Before restore backup" has its checkmark yet.
    public var isCurrentDataSaved: Bool {
        (restoreStep ?? .savingCurrentData) > .savingCurrentData
    }

    /// The step VoiceOver reads with the progress bar, so it hears more than a percentage (UI Designer).
    public var restoreStepText: String {
        isCurrentDataSaved ? BackupPresentation.replacingDataStep : BackupPresentation.savedCurrentDataStep
    }

    public func record(_ id: UUID) -> BackupRecord? {
        records.first { $0.id == id }
    }

    public func row(_ id: UUID) -> BackupRowModel? {
        rows.first { $0.id == id }
    }

    /// Reads the list again. A Backups folder that can't be read doesn't throw: it's the list's "Couldn’t Load
    /// Backups" state, and the next load that works clears it (R3, D211.5). It throws only when cancelled.
    public func load() async throws {
        let overview: BackupOverview
        do {
            overview = try await useCases.list.overview()
        } catch BackupError.loadFailed {
            isLoadFailed = true
            return
        }
        isLoadFailed = false
        let moment = now()
        presentation.retention = overview.retention
        records = overview.backups
        rows = overview.backups.map { presentation.row($0, now: moment) }
        if let last = overview.lastBackup {
            lastBackupText =
                presentation.lastBackup(presentation.date(last.createdAt, now: moment))
        } else {
            lastBackupText = nil
        }
        failureMessage = overview.lastFailure == .notEnoughStorage ? presentation.notEnoughStorageMessage : nil
        isBackingUp = useCases.make.isBusy && restoreStep == nil
    }

    /// Runs `work`, then reads the list again whether it worked or not, and rethrows its error.
    private func reloading<Value>(_ work: () async throws -> Value) async throws -> Value {
        let value: Value
        do {
            value = try await work()
        } catch {
            try? await load()
            throw error
        }
        try await load()
        return value
    }

    // MARK: Back Up Now

    /// Shows the indeterminate "Backup in progress…" row, with Back Up Now and Restore disabled, and has VoiceOver
    /// announce the start and the finish (D179.2). A full disk is the failure line; any other error is thrown.
    public func backUpNow() async throws {
        guard actionsEnabled else {
            return
        }
        isBackingUp = true
        announce(BackupPresentation.backupStartedAnnouncement)
        var finished = BackupPresentation.backupFailedAnnouncement
        var failure: (any Error)?
        do {
            _ = try await useCases.make.backUpNow()
            finished = BackupPresentation.backupFinishedAnnouncement
        } catch BackupError.notEnoughStorage {
            // Also shown by the failure line from the catalog.
            finished = presentation.notEnoughStorageMessage
        } catch BackupError.busy {
            // Another backup is running; nothing is queued.
        } catch {
            failure = error
        }
        isBackingUp = false
        defer { announce(finished) }
        if let failure {
            try? await load()
            throw failure
        }
        try await load()
    }

    /// The background trigger (D62): `backUpAutomaticallyIfNeeded` inside a background-time assertion, cancelled
    /// cleanly if the time runs out (`BackgroundBackupRun`). One at a time. Returns the task, for tests to await.
    @discardableResult
    public func backUpInBackground(_ activity: (any BackgroundActivity)?) -> Task<Void, Never>? {
        guard backgroundRun == nil else {
            return nil
        }
        let run = BackgroundBackupRun(activity: activity)
        backgroundRun = run
        run.start(
            { [weak self] in
                await self?.backUpAutomaticallyIfNeeded()
            },
            expired: { [weak self] in
                // The automatic backup running now, this one's or a launch backup it joined.
                self?.automaticRun?.cancel()
            },
            finished: { [weak self] in
                self?.backgroundRun = nil
            },
        )
        return run.task
    }

    /// The launch and background trigger (D62). Errors only update the failure line. A call while one is running
    /// waits for that one instead, so the background trigger's assertion covers a launch backup that's still going,
    /// and cancelling the caller cancels it (Tech Architect, non-blocking 1).
    public func backUpAutomaticallyIfNeeded() async {
        if let automaticRun {
            await Self.joining(automaticRun)
            return
        }
        guard actionsEnabled else {
            return
        }
        let run = Task { [weak self] in
            guard let self else {
                return
            }
            isBackingUp = true
            _ = try? await useCases.make.backUpAutomaticallyIfNeeded()
            isBackingUp = false
            try? await load()
            automaticRun = nil
        }
        automaticRun = run
        await Self.joining(run)
    }

    private static func joining(_ run: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await run.value
        } onCancel: {
            run.cancel()
        }
    }

    // MARK: Delete (D116.1): confirm, then App Lock

    /// Whether the backup is being written to an export file, in any window. Read through the use case, so every
    /// window showing it updates when an export starts and ends (D208.1).
    public func isExporting(_ id: UUID) -> Bool {
        useCases.export.exportCount(of: id) > 0
    }

    /// Delete Backup and Delete… are off while actions are off, and while the backup is being exported (D208.1).
    public func deleteEnabled(for id: UUID) -> Bool {
        actionsEnabled && !isExporting(id)
    }

    /// The row to confirm deleting, or `nil` while its Delete is off.
    public func deletePrompt(for id: UUID) -> BackupRowModel? {
        guard deleteEnabled(for: id) else {
            return nil
        }
        return row(id)
    }

    /// After the confirmation: App Lock, then the delete. Cancelling App Lock changes nothing. A backup that another
    /// window started exporting while the confirmation was open throws `exporting`, before App Lock is asked, and
    /// nothing is deleted or queued (D208.1).
    public func delete(_ row: BackupRowModel) async throws {
        guard actionsEnabled else {
            return
        }
        guard !isExporting(row.id) else {
            throw BackupError.exporting
        }
        guard await useCases.authentication.authenticate(for: .deleteBackup) else {
            return
        }
        try await reloading { try await useCases.delete.deleteBackup(id: row.id) }
    }

    // MARK: Keep (D195.4, D195.5): lowering N or M confirms, then App Lock, then cleanup

    /// A stepper changed. Raising, or lowering when nothing would be deleted, just saves (L14) and returns `nil`.
    /// Lowering that deletes backups saves nothing yet: it returns the prompt with the exact count (L12), for the
    /// window that asked to show. Cancel is just dropping it (L13).
    public func proposeRetention(_ proposed: BackupRetention) async throws -> BackupPrunePrompt? {
        let previous = presentation.retention
        guard retentionEnabled, proposed != previous else {
            return nil
        }
        let plan =
            proposed.isLower(than: previous)
            ? try await useCases.retention.cleanupPlan(for: proposed)
            : BackupCleanupPlan(retention: proposed)
        if plan.backups.isEmpty {
            try await reloading { _ = try await useCases.retention.apply(plan) }
            return nil
        }
        let count = plan.backups.count
        return BackupPrunePrompt(
            plan: plan,
            previous: previous,
            title: presentation.pruneTitle(count),
            message: presentation.pruneMessage(count),
            confirmTitle: presentation.pruneConfirm(count),
        )
    }

    /// 'Delete 4 Backups', with the prompt it presented: App Lock, then the new N and M are saved and cleanup
    /// deletes what was counted (L13). Cancelling the authentication is the same as Cancel: nothing changes.
    public func confirmPrune(_ prompt: BackupPrunePrompt) async throws {
        guard actionsEnabled, await useCases.authentication.authenticate(for: .pruneBackups) else {
            return
        }
        try await reloading { _ = try await useCases.retention.apply(prompt.plan) }
    }

    // MARK: Export (D63, D182.4): App Lock, then the Export sheet, then the share sheet or save panel

    /// App Lock, then the Export sheet's contents. `nil` if App Lock was cancelled, or for a damaged or
    /// newer-format backup, which has no Export… (D196.3, D197.2).
    public func exportPrompt(for id: UUID) async -> BackupExportPrompt? {
        guard actionsEnabled, let record = record(id), record.isRestorable,
            await useCases.authentication.authenticate(for: .exportBackup)
        else {
            return nil
        }
        let moment = now()
        return BackupExportPrompt(
            record: record,
            dateText: presentation.date(of: record, now: moment),
            summary: presentation.exportSummary(record, now: moment),
        )
    }

    /// The Export sheet's Export button: the file for the share sheet or save panel. There's no password and no
    /// extra step (D182.4).
    public func exportFile(_ prompt: BackupExportPrompt) async throws -> BackupExportFile? {
        guard actionsEnabled else {
            return nil
        }
        let fileName = presentation.fileName(for: prompt.record)
        let export = try await useCases.export.exportBackup(id: prompt.record.id, named: fileName)
        return BackupExportFile(export: export, fileName: fileName)
    }

    /// Removes an export's file once its save panel or share sheet has closed, saved or cancelled (B2).
    public func discardExport(_ file: BackupExportFile) {
        useCases.export.discardExport(file.export)
    }

    // MARK: Restore (D63, D116.2, D182.1): App Lock, the warning, the Before restore backup, then progress

    /// Restore…: App Lock, then the checked backup's warning. `nil` if App Lock was cancelled, or for a damaged
    /// or newer-format backup, which has no Restore… (D196.3, D197.2).
    public func restorePrompt(for id: UUID) async throws -> BackupRestorePrompt? {
        guard actionsEnabled, record(id)?.isRestorable == true,
            await useCases.authentication.authenticate(for: .restoreBackup)
        else {
            return nil
        }
        return try await prompt(opening: .stored(id))
    }

    /// 'Restore from File…' or File > Restore from Backup…, the only import routes in #40 (D197.3, L39): App
    /// Lock, then the checked file's warning. No password is asked (D182.1).
    public func restorePrompt(forFile archive: BackupArchiveSource) async throws -> BackupRestorePrompt? {
        guard actionsEnabled, await useCases.authentication.authenticate(for: .restoreBackup) else {
            return nil
        }
        return try await prompt(opening: .archive(archive))
    }

    /// The progress screen's line for `prompt`: the backup's date and counts.
    public func restoringSummary(for prompt: BackupRestorePrompt) -> String {
        [
            presentation.date(prompt.manifest.createdAt, now: now()),
            presentation.counts(prompt.manifest.accountCount, prompt.manifest.transactionCount),
        ]
        .joined(separator: " · ")
    }

    /// The warning's Restore button: the Before restore backup, then the restore, with `restoreStep` following
    /// it. `nil` while actions are off.
    public func restore(_ prompt: BackupRestorePrompt) async throws -> BackupRestoreOutcome? {
        guard actionsEnabled else {
            return nil
        }
        restoreStep = .savingCurrentData
        defer { restoreStep = nil }
        return try await reloading {
            let before = try await useCases.restore.restore(prompt.source) { [weak self] step in
                self?.restoreStep = step
            }
            return BackupRestoreOutcome(
                toast: BackupPresentation.restoredToast,
                restoredMessage: presentation.restoredMessage(before: before, now: now()),
            )
        }
    }

    private func prompt(opening source: BackupSource) async throws -> BackupRestorePrompt {
        let manifest = try await useCases.restore.checkBackup(source)
        return BackupRestorePrompt(
            message: presentation.restoreMessage(for: manifest, now: now()),
            source: source,
            manifest: manifest,
        )
    }
}
