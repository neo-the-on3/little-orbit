import Foundation
import LittleOrbitDomain

/// Copy and formatting for the Backups screens (#40), shared by iOS and macOS. Titles and buttons use title case;
/// body text, messages and footnotes use sentence case (D118.4, D173.10). No amount is ever shown (D62).
///
/// The sentences are English for now. They move to `Localizable.xcstrings` with positional arguments in the
/// app-wide localization follow-up, once #87's `FeatureText.format` pattern is on main (N1).
public struct BackupPresentation: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone
    public var device: BackupDevice

    public init(locale: Locale = .current, timeZone: TimeZone = .current, device: BackupDevice) {
        self.locale = locale
        self.timeZone = timeZone
        self.device = device
    }

    /// "iPhone", "iPad" or "Mac", as in "Backups stay on this iPhone".
    public var deviceName: String {
        device.name
    }

    private var retention: Int {
        BackupPolicy.automaticRetention
    }

    /// "tap" on iPhone and iPad, "click" on Mac (UI Designer, frame 168:2566).
    private var pressVerb: String {
        device == .mac ? "click" : "tap"
    }

    // MARK: Buttons and titles (D173.10)

    public static let backUpNow = "Back Up Now"
    public static let restoreFromFile = "Restore from File…"
    public static let restoreFromBackupMenu = "Restore from Backup…"
    public static let restoreEllipsis = "Restore…"
    public static let exportEllipsis = "Export…"
    public static let deleteBackup = "Delete Backup"
    public static let deleteEllipsis = "Delete…"
    public static let backupInProgress = "Backup in progress…"
    /// VoiceOver announcements for Back Up Now (D179.2, UI Designer). A full disk announces
    /// `notEnoughStorageMessage` instead of the finish.
    public static let backupStartedAnnouncement = "Backup in progress"
    public static let backupFinishedAnnouncement = "Backup complete"
    public static let backupFailedAnnouncement = "Backup failed"
    /// The iOS backup detail's title; the date is in its Date row (UI Designer, frame 165:504).
    public static let detailTitle = "Backup"
    /// The restore steps under the progress bar (UI Designer, frames 165:1028 and 169:5070).
    public static let savedCurrentDataStep = "Current data saved as a Before restore backup"
    public static let replacingDataStep = "Replacing data…"
    /// Exported file names start with this (D116.4).
    public static let fileNamePrefix = "little-orbit"
    public static let damagedTitle = "This Backup Is Damaged"
    public static let damagedMessage = "It can’t be restored. Your data hasn’t changed."
    public static let newerFormatTitle = "Update little-orbit to Restore This Backup"
    public static let newerFormatMessage =
        "This backup was made with a newer version of little-orbit. Your data hasn’t changed."
    public static let incorrectPassword = "Incorrect password. Try again."
    public static let restoreTitle = "Restore This Backup?"
    public static let restoringTitle = "Restoring Backup"
    public static let restoredToast = "Backup restored · Before restore backup saved"
    public static let deleteTitle = "Delete This Backup?"
    public static let emptyTitle = "No Backups Yet"
    public static let exportTitle = "Export Backup"
    public static let enterPasswordTitle = "Enter Password"
    public static let passwordProtectedFooter =
        "This backup is protected with a password. Enter it to continue to the restore warning."
    public static let forgottenPasswordFooter = "A forgotten password can’t be recovered."
    public static let unencryptedWarning = "This file isn’t encrypted and contains all your financial data."
    public static let passwordTooShort = "Use at least 8 characters."
    public static let passwordsDontMatch = "Passwords don’t match."
    public static let restoreInterruptedNote =
        "Keep little-orbit open. If the restore is interrupted, your data stays exactly as it was before."

    // MARK: Device-specific copy

    public var emptyMessage: String {
        if device == .mac {
            // Frame 168:2267.
            return "The first automatic backup is made after you change something. You can also back up now or "
                + "restore from a backup file."
        }
        return "little-orbit makes a backup once a day after you change something and keeps the \(retention) most "
            + "recent. Backups stay on this \(deviceName)."
    }

    public var retentionNote: String {
        "little-orbit backs up once a day after you change something and keeps the \(retention) most recent automatic "
            + "backups. Manual and Before restore backups stay until you delete them."
    }

    public var storageFooter: String {
        if device == .mac {
            return "Backups stay on this \(deviceName), inside little-orbit’s own container, and are never uploaded. "
                + "Export one to keep a copy somewhere else."
        }
        return "Backups stay on this \(deviceName) and are never uploaded. Export one to keep a copy somewhere else."
    }

    public var notEnoughStorageMessage: String {
        "Last backup failed: not enough storage. Free up space on this \(deviceName), then \(pressVerb) Back Up Now. "
            + "No older backup was removed."
    }

    public var deleteMessage: String {
        "It’s removed from this \(deviceName). This can’t be undone."
    }

    public var exportPasswordFooter: String {
        "Add a password to encrypt the file on this \(deviceName). Use at least 8 characters. There’s no hint, "
            + "and a forgotten password can’t be recovered. If you forget this password, this backup can’t be opened."
    }

    public var advancedFooter: String {
        "Automatic daily backups, Back Up Now, export and restore. Backups stay on this \(deviceName)."
    }

    /// The Delete footnote for one backup, naming the device's biometry (D116.1, UI Designer, frame 165:599).
    /// The retention sentence is only for automatic backups.
    public func deleteFootnote(_ method: AppUnlockMethod, kind: BackupKind) -> String {
        let unlock =
            switch method {
            case .faceID: "Face ID or the app passcode"
            case .touchID: "Touch ID or the app passcode"
            case .opticID: "Optic ID or the app passcode"
            case .passcodeOnly: "the app passcode"
            }
        let lead =
            switch kind {
            case .automatic: "little-orbit keeps the \(retention) most recent automatic backups."
            case .manual, .beforeRestore: "Manual and Before restore backups stay until you delete them."
            }
        return "\(lead) With App Lock on, Delete asks for \(unlock) first."
    }

    /// The macOS tab's inline line after a restore (UI Designer, frame 169:5253). iOS shows `restoredToast`.
    public func restoredMessage(before: BackupRecord, now: Date) -> String {
        "Backup restored. Your previous data is saved as a Before restore backup (\(date(before.createdAt, now: now)))."
    }

    /// The suggested export name, `little-orbit YYYY-MM-DD HHmm[ n].littleorbit-backup` (D116.4, D118.3): the
    /// creation time in this presentation's (the device's current) time zone, 24-hour, no seconds (D133), and the
    /// Finder-style suffix from the index fixed when the backup was made (D173.11, D174).
    public func fileName(for record: BackupRecord) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.createdAt)
        let date = "\(Self.pad(parts.year ?? 0, 4))-\(Self.pad(parts.month ?? 0, 2))-\(Self.pad(parts.day ?? 0, 2))"
        let time = "\(Self.pad(parts.hour ?? 0, 2))\(Self.pad(parts.minute ?? 0, 2))"
        let suffix = record.nameIndex > 1 ? " \(record.nameIndex)" : ""
        return "\(Self.fileNamePrefix) \(date) \(time)\(suffix).\(BackupFormat.fileExtension)"
    }

    /// The restore progress bar's value for each step (S54).
    public static func fraction(_ step: BackupRestoreStep) -> Double {
        switch step {
        case .savingCurrentData: 0.2
        case .replacingData: 0.6
        case .finished: 1
        }
    }

    /// "Version 1" in the iOS backup detail; the list line keeps "Format 1" (frame 165:504).
    public static func version(_ version: Int) -> String {
        "Version \(version)"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    public func restoreMessage(for manifest: BackupManifest, now: Date) -> String {
        let summary = [date(manifest.createdAt, now: now), counts(manifest.accountCount, manifest.transactionCount)]
            .joined(separator: " · ")
        return "All data on this \(deviceName) will be replaced with this backup (\(summary)). Your current data is "
            + "saved first as a Before restore backup, so you can go back. App Lock, Hide amounts, report "
            + "exclusions and theme on this \(deviceName) don’t change."
    }

    // MARK: Values

    public static func kind(_ kind: BackupKind) -> String {
        switch kind {
        case .automatic: "Automatic"
        case .manual: "Manual"
        case .beforeRestore: "Before restore"
        }
    }

    /// "Today, 9:12 AM", "Yesterday, 8:47 PM", otherwise "19 Oct 2026, 10:03 AM", in the current time zone (D133).
    public func date(_ date: Date, now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let time = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).hour().minute()
        )
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today, \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday, \(time)"
        }
        let day = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).day().month(.abbreviated).year()
        )
        return "\(day), \(time)"
    }

    /// The stored file's size, attachments included (D116.5), formatted for the locale.
    public func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    public func counts(_ accounts: Int, _ transactions: Int) -> String {
        "\(accounts) \(accounts == 1 ? "account" : "accounts") · "
            + "\(transactions) \(transactions == 1 ? "transaction" : "transactions")"
    }

    public static func format(_ version: Int) -> String {
        "Format \(version)"
    }

    /// The macOS Export sheet's summary of the selected backup (S64, S76).
    public func exportSummary(_ record: BackupRecord, now: Date) -> String {
        var parts = [
            "Backup from \(date(record.createdAt, now: now))",
            Self.kind(record.kind),
            "\(record.accountCount) \(record.accountCount == 1 ? "account" : "accounts")",
            "\(record.transactionCount) \(record.transactionCount == 1 ? "transaction" : "transactions")",
        ]
        if record.attachmentCount > 0 {
            parts.append("\(record.attachmentCount) \(record.attachmentCount == 1 ? "attachment" : "attachments")")
        }
        return parts.joined(separator: " · ")
    }

    public func row(_ record: BackupRecord, now: Date) -> BackupRowModel {
        let title = date(record.createdAt, now: now)
        let kind = Self.kind(record.kind)
        let sizeText = size(record.byteSize)
        let countsText = counts(record.accountCount, record.transactionCount)
        return BackupRowModel(
            id: record.id,
            kind: record.kind,
            title: title,
            kindText: kind,
            sizeText: sizeText,
            formatText: Self.format(record.formatVersion),
            countsText: countsText,
            detailLine: [kind, sizeText, Self.format(record.formatVersion)].joined(separator: " · "),
            accessibilityLabel: [
                title, "\(kind) backup", sizeText, countsText.replacingOccurrences(of: " · ", with: ", "),
            ]
            .joined(separator: ", "),
            accountCount: record.accountCount,
            transactionCount: record.transactionCount,
            attachmentCount: record.attachmentCount,
            formatVersion: record.formatVersion,
        )
    }
}

/// One backup in the list and its detail. Never carries an amount.
public struct BackupRowModel: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: BackupKind
    /// "Today, 9:12 AM".
    public var title: String
    public var kindText: String
    public var sizeText: String
    public var formatText: String
    /// "5 accounts · 120 transactions".
    public var countsText: String
    /// "Automatic · 1.8 MB · Format 1".
    public var detailLine: String
    /// "Today, 9:12 AM, Automatic backup, 1.8 MB, 5 accounts, 120 transactions" (S35).
    public var accessibilityLabel: String
    public var accountCount: Int
    public var transactionCount: Int
    /// The detail hides its Attachments row when this is 0 (S61, S72).
    public var attachmentCount: Int
    public var formatVersion: Int
}

/// The device the copy talks about ("this iPhone"). The App target picks it; Features keeps the words.
public enum BackupDevice: Sendable, Equatable {
    case iPhone
    case iPad
    case mac

    public var name: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }
}
