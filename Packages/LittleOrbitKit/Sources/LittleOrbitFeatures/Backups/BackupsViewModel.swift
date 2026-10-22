import Foundation
import LittleOrbitDomain
import Observation

/// An alert the Backups screens show. Each one leaves the data unchanged.
public struct BackupAlert: Identifiable, Equatable, Sendable {
    public var id: String { title + message }
    public var title: String
    public var message: String

    public static let damaged = BackupAlert(
        title: BackupPresentation.damagedTitle,
        message: BackupPresentation.damagedMessage,
    )
    public static let newerFormat = BackupAlert(
        title: BackupPresentation.newerFormatTitle,
        message: BackupPresentation.newerFormatMessage,
    )
}

/// An exported backup with its suggested name, for `fileExporter`.
public struct BackupExportFile: Equatable, Sendable {
    public var data: Data
    /// `little-orbit YYYY-MM-DD HHmm[ n].littleorbit-backup`.
    public var fileName: String
    public var isEncrypted: Bool

    public init(data: Data, fileName: String, isEncrypted: Bool) {
        self.data = data
        self.fileName = fileName
        self.isEncrypted = isEncrypted
    }
}

/// The restore warning, with the checked backup it would restore.
public struct BackupRestorePrompt: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var message: String
    public var contents: BackupContents
}

/// The Enter Password step for an encrypted backup file (D63, D118.4).
public struct BackupPasswordPrompt: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var source: BackupSource
    public var fileName: String
    /// "Incorrect password. Try again." after a wrong attempt. Retries are unlimited.
    public var errorMessage: String?
}

/// Settings > Backups on iOS and the Backups settings tab on macOS (#40).
///
/// Depends only on the backup use-case protocols. Restore, Export and Delete ask the App Lock hook first
/// (`AppAuthenticationUseCase`, D63); Delete confirms before that (S51). While a backup or restore runs, the other
/// actions are disabled, never queued (D118.5).
@MainActor
@Observable
public final class BackupsViewModel {
    public private(set) var rows: [BackupRowModel] = []
    public private(set) var records: [BackupRecord] = []
    /// "Last backup: Today, 9:12 AM." with the retention rule, or only the rule when there are no backups.
    public private(set) var lastBackupText: String?
    public private(set) var failureMessage: String?
    public private(set) var isBackingUp = false
    /// Non-nil while a restore runs: the progress screen, with no Cancel (D116.2).
    public private(set) var restoreStep: BackupRestoreStep?
    public private(set) var restoringSummary: String?

    public var alert: BackupAlert?
    public var restorePrompt: BackupRestorePrompt?
    public var passwordPrompt: BackupPasswordPrompt?
    public var deletePrompt: BackupRowModel?
    public var exportForm: ExportBackupForm?
    /// The file to hand to the share sheet or save panel.
    public var pendingExport: BackupExportFile?
    /// iOS: the toast "Backup restored · Before restore backup saved".
    public var toast: String?
    /// macOS: the inline line in the Backups tab after a restore (frame 169:5253).
    public private(set) var restoredMessage: String?
    public var errorMessage: String?

    public let presentation: BackupPresentation
    private let useCases: BackupUseCases
    private let now: @MainActor () -> Date
    private let announce: @MainActor (String) -> Void

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

    public var isEmpty: Bool {
        rows.isEmpty
    }

    /// Restore, Export, Delete and Back Up Now are off while a backup or restore runs (D118.5).
    public var actionsEnabled: Bool {
        !isBackingUp && restoreStep == nil
    }

    /// The Delete footnote for one backup: the retention sentence only for automatic ones (UI Designer).
    public func deleteFootnote(for id: UUID) -> String {
        presentation.deleteFootnote(useCases.authentication.unlockMethod(), kind: record(id)?.kind ?? .manual)
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

    public func load() {
        do {
            let overview = try useCases.list.overview()
            let moment = now()
            records = overview.backups
            rows = overview.backups.map { presentation.row($0, now: moment) }
            if let last = overview.lastBackup {
                lastBackupText =
                    "Last backup: \(presentation.date(last.createdAt, now: moment)). "
                    + presentation.retentionNote
            } else {
                lastBackupText = nil
            }
            failureMessage = overview.lastFailure == .notEnoughStorage ? presentation.notEnoughStorageMessage : nil
            isBackingUp = useCases.make.isBusy && restoreStep == nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Back Up Now

    /// Shows the indeterminate "Backup in progress…" row, with Back Up Now and Restore disabled, and has VoiceOver
    /// announce the start and the finish (D179.2).
    public func backUpNow() async {
        guard actionsEnabled else {
            return
        }
        isBackingUp = true
        announce(BackupPresentation.backupStartedAnnouncement)
        var finished = BackupPresentation.backupFailedAnnouncement
        defer {
            isBackingUp = false
            load()
            announce(finished)
        }
        do {
            _ = try await useCases.make.backUpNow()
            finished = BackupPresentation.backupFinishedAnnouncement
        } catch BackupError.notEnoughStorage {
            // Also shown by the failure line from the catalog.
            finished = presentation.notEnoughStorageMessage
        } catch BackupError.busy {
            // Another backup is running; nothing is queued.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The launch and background trigger (D62). Errors only update the failure line.
    public func backUpAutomaticallyIfNeeded() async {
        guard actionsEnabled else {
            return
        }
        isBackingUp = true
        defer {
            isBackingUp = false
            load()
        }
        _ = try? await useCases.make.backUpAutomaticallyIfNeeded()
    }

    // MARK: Delete (D116.1): confirm, then App Lock

    public func requestDelete(_ id: UUID) {
        guard actionsEnabled, let row = row(id) else {
            return
        }
        deletePrompt = row
    }

    public func confirmDelete() async {
        guard let row = deletePrompt else {
            return
        }
        deletePrompt = nil
        guard actionsEnabled, await useCases.authentication.authenticate(for: .deleteBackup) else {
            return
        }
        do {
            try useCases.delete.deleteBackup(id: row.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        load()
    }

    // MARK: Export (D63): App Lock, then the password sheet, then the share sheet or save panel

    public func requestExport(_ id: UUID) async {
        guard actionsEnabled, let record = record(id),
            await useCases.authentication.authenticate(for: .exportBackup)
        else {
            return
        }
        exportForm = ExportBackupForm(record: record)
    }

    public func export(_ form: ExportBackupForm) async {
        guard form.canExport, actionsEnabled else {
            return
        }
        do {
            let export = try await useCases.export.exportBackup(id: form.record.id, password: form.exportPassword)
            pendingExport = BackupExportFile(
                data: export.data,
                fileName: presentation.fileName(for: export.record),
                isEncrypted: export.isEncrypted,
            )
            exportForm = nil
        } catch {
            exportForm = nil
            show(error)
        }
    }

    // MARK: Restore (D63, D116.2): App Lock, password if needed, warning, then all-or-nothing

    public func requestRestore(_ id: UUID) async {
        guard actionsEnabled, await useCases.authentication.authenticate(for: .restoreBackup) else {
            return
        }
        await open(.stored(id), fileName: "", password: nil)
    }

    /// 'Restore from File…', File > Restore from Backup… or a file opened from Files or Finder.
    public func restoreFromFile(_ data: Data, fileName: String) async {
        guard actionsEnabled, await useCases.authentication.authenticate(for: .restoreBackup) else {
            return
        }
        await open(.file(data), fileName: fileName, password: nil)
    }

    public func submitPassword(_ password: String) async {
        guard let prompt = passwordPrompt else {
            return
        }
        await open(prompt.source, fileName: prompt.fileName, password: password)
    }

    public func cancelPassword() {
        passwordPrompt = nil
    }

    public func cancelRestore() {
        restorePrompt = nil
    }

    public func confirmRestore() async {
        guard let prompt = restorePrompt, actionsEnabled else {
            return
        }
        restorePrompt = nil
        restoringSummary = [
            presentation.date(prompt.contents.manifest.createdAt, now: now()),
            presentation.counts(prompt.contents.manifest.accountCount, prompt.contents.manifest.transactionCount),
        ]
        .joined(separator: " · ")
        restoreStep = .savingCurrentData
        restoredMessage = nil
        do {
            let before = try await useCases.restore.restore(prompt.contents) { [weak self] step in
                self?.restoreStep = step
            }
            toast = BackupPresentation.restoredToast
            restoredMessage = presentation.restoredMessage(before: before, now: now())
        } catch {
            show(error)
        }
        restoreStep = nil
        restoringSummary = nil
        load()
    }

    private func open(_ source: BackupSource, fileName: String, password: String?) async {
        do {
            let contents = try await useCases.restore.openBackup(source, password: password)
            passwordPrompt = nil
            restorePrompt = BackupRestorePrompt(
                message: presentation.restoreMessage(for: contents.manifest, now: now()),
                contents: contents,
            )
        } catch BackupError.passwordRequired {
            passwordPrompt = BackupPasswordPrompt(source: source, fileName: fileName)
        } catch BackupError.incorrectPassword {
            passwordPrompt = BackupPasswordPrompt(
                source: source,
                fileName: fileName,
                errorMessage: BackupPresentation.incorrectPassword,
            )
        } catch {
            passwordPrompt = nil
            show(error)
        }
    }

    private func show(_ error: any Error) {
        switch error as? BackupError {
        case .damaged, .notFound:
            alert = .damaged
        case .newerFormat:
            alert = .newerFormat
        case .notEnoughStorage:
            failureMessage = presentation.notEnoughStorageMessage
        case .busy:
            break
        default:
            errorMessage = error.localizedDescription
        }
    }
}
