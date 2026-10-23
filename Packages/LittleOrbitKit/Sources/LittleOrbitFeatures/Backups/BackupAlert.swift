import Foundation

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
    /// The Before restore backup didn't check out, so nothing was replaced (D63, B3, D207.1).
    public static let beforeRestoreFailed = BackupAlert(
        title: BackupPresentation.beforeRestoreFailedTitle,
        message: BackupPresentation.beforeRestoreFailedMessage,
    )
    /// A picked file couldn't be read at all (D207.2). One that's read but fails a check is `damaged`.
    public static let unreadableFile = BackupAlert(
        title: BackupPresentation.unreadableFileTitle,
        message: BackupPresentation.unreadableFileMessage,
    )
    /// A backup on the device couldn't be read for a restore. It stays restorable (D208.2).
    public static let unreadableBackup = BackupAlert(
        title: BackupPresentation.unreadableFileTitle,
        message: BackupPresentation.unreadableBackupMessage,
    )
    /// Lowering N or M while a backup can't be read: nothing deleted, N and M unchanged (R3, D208.3).
    public static let cleanupBlocked = BackupAlert(
        title: BackupPresentation.cleanupBlockedTitle,
        message: BackupPresentation.cleanupBlockedMessage,
    )
    /// Delete confirmed while the backup is being exported: nothing deleted or queued (D208.1).
    public static let deleteWhileExporting = BackupAlert(
        title: BackupPresentation.deleteWhileExportingTitle,
        message: BackupPresentation.deleteWhileExportingMessage,
    )
    /// A full disk while the Before restore backup was made: nothing was replaced (D211.8).
    public static let notEnoughStorageToRestore = BackupAlert(
        title: BackupPresentation.notEnoughStorageToRestoreTitle,
        message: BackupPresentation.notEnoughStorageToRestoreMessage,
    )
    /// The export file couldn't be created or written, a full disk included (D211.4).
    public static let exportFailed = BackupAlert(
        title: BackupPresentation.exportFailedTitle,
        message: BackupPresentation.exportFailedMessage,
    )
    /// After the Before restore backup was made, the restore couldn't finish: nothing was replaced (D211.1).
    public static let restoreFailed = BackupAlert(
        title: BackupPresentation.beforeRestoreFailedTitle,
        message: BackupPresentation.restoreFailedMessage,
    )
    /// Back Up Now failed other than with a full disk, which is the list's line (D211.2).
    public static let backUpFailed = BackupAlert(
        title: BackupPresentation.backUpFailedTitle,
        message: BackupPresentation.backUpFailedMessage,
    )
    /// The backup's folder couldn't be removed (D211.3). An export in progress is `deleteWhileExporting`.
    public static let deleteFailed = BackupAlert(
        title: BackupPresentation.deleteFailedTitle,
        message: BackupPresentation.deleteFailedMessage,
    )
    /// Lowering N or M failed before anything was saved or deleted (D211.6).
    public static let cleanupFailed = BackupAlert(
        title: BackupPresentation.cleanupBlockedTitle,
        message: BackupPresentation.cleanupFailedMessage,
    )
}
