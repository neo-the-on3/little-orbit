import Foundation
import LittleOrbitDomain

extension BackupsViewModel {
    /// How a window shows `error`. Not enough storage on Back Up Now is the failure line, read with the list;
    /// another backup running needs nothing (D118.5), and a list that can't load is the list's own state (D211.5).
    /// Any other error is "Something Went Wrong" with the catalog's text, never the error's own description
    /// (D211.9).
    public static func feedback(for error: any Error) -> BackupFeedback {
        guard let backup = error as? BackupError else {
            // Never the error's own text: it can name the store's files and folders (Tester F3, D211.9).
            return .error(BackupPresentation.somethingWentWrongMessage)
        }
        return alert(for: backup).map(BackupFeedback.alert) ?? .none
    }

    /// Each backup error's alert, or `nil` for the three that aren't alerts. No `default`, so a new case doesn't
    /// compile until it has one (Tech Architect). One case per error is the point, so the count isn't complexity.
    private static func alert(for error: BackupError) -> BackupAlert? {  // swiftlint:disable:this cyclomatic_complexity
        switch error {
        case .damaged, .notFound: .damaged
        case .newerFormat: .newerFormat
        case .beforeRestoreFailed: .beforeRestoreFailed
        case .unreadableFile: .unreadableFile
        case .unreadableBackup: .unreadableBackup
        case .cleanupBlocked: .cleanupBlocked
        case .exporting: .deleteWhileExporting
        case .notEnoughStorageToRestore: .notEnoughStorageToRestore
        case .exportFailed: .exportFailed
        case .cleanupFailed: .cleanupFailed
        case .restoreFailed: .restoreFailed
        case .backUpFailed: .backUpFailed
        case .deleteFailed: .deleteFailed
        case .notEnoughStorage, .busy, .loadFailed: nil
        }
    }
}
