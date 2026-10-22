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
    /// N and M, for the footer and the Automatic footnote (D195.4). The view model keeps it current.
    public var retention: BackupRetention

    public init(
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        device: BackupDevice,
        retention: BackupRetention = .default,
    ) {
        self.locale = locale
        self.timeZone = timeZone
        self.device = device
        self.retention = retention
    }

    /// "iPhone", "iPad" or "Mac", as in "Backups stay on this iPhone".
    public var deviceName: String {
        device.name
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
    /// The iOS Export sheet's navigation-bar button: no ellipsis, since the share sheet follows directly
    /// (UI Designer, frame 277:4915). macOS keeps "Export…" (277:4581).
    public static let exportConfirm = "Export"
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
    public static let restoreTitle = "Restore This Backup?"
    public static let restoringTitle = "Restoring Backup"
    public static let restoredToast = "Backup restored · Before restore backup saved"
    public static let deleteTitle = "Delete This Backup?"
    public static let emptyTitle = "No Backups Yet"
    public static let exportTitle = "Export Backup"
    /// The retention section (L11): standard Stepper rows, as UI Designer approved.
    public static let keepHeader = "Keep"
    public static let recentAutomaticBackups = "Recent Automatic Backups"
    public static let monthlyBackups = "Monthly Backups"
    public static let monthlyOff = "Off"
    /// A damaged backup in the list and its detail (D196.3, L29).
    public static let damagedLabel = "Damaged"
    public static let damagedExplanation =
        "This backup is damaged and can’t be restored. Some of its files are missing or have changed."
    /// A newer-format backup in the list, and the line its detail adds (D197.2, L35).
    public static let newerFormatNote = "Made by a newer version of little-orbit."
    public static let newerFormatDetail = "Update little-orbit to restore it."
    /// The kind of a damaged folder whose manifest was never read.
    public static let unknownKind = "Unknown"
    /// The Export sheet's one line, on every export (D182.4).
    public static let unencryptedWarning = "This file isn’t encrypted and contains all your financial data."
    /// The note's SF Symbol, shown in the warning colour (UI Designer, frames 277:4915 and 277:4581).
    public static let unencryptedWarningSymbol = "exclamationmark.triangle.fill"
    /// What VoiceOver says for the warning icon, before the note.
    public static let warning = "Warning"
    /// The note as one VoiceOver element: "Warning, This file isn’t encrypted and contains all your financial
    /// data." (UI Designer, after Tester's 6335997896.)
    public static let unencryptedWarningAccessibilityLabel = "\(warning), \(unencryptedWarning)"
    public static let restoreInterruptedNote =
        "Keep little-orbit open. If the restore is interrupted, your data stays exactly as it was before."

    // MARK: Device-specific copy

    public var emptyMessage: String {
        if device == .mac {
            // Frame 168:2267.
            return "The first automatic backup is made after you change something. You can also back up now or "
                + "restore from a backup file."
        }
        return "little-orbit makes a backup once a day after you change something. Backups stay on this "
            + "\(deviceName)."
    }

    /// After "Last backup: …": when automatic backups run.
    public var retentionNote: String {
        "little-orbit backs up once a day after you change something."
    }

    /// The footer under Keep (L11), with the current N and M.
    public var keepFooter: String {
        let recent =
            retention.recentAutomatic == 1
            ? "your most recent automatic backup"
            : "your \(retention.recentAutomatic) most recent automatic backups"
        let monthly =
            switch retention.monthlyMonths {
            case 0: ""
            case 1: " and the first automatic backup of this month"
            default: " and the first automatic backup of each month for \(retention.monthlyMonths) months"
            }
        return "little-orbit keeps \(recent)\(monthly). Manual and Before restore backups are kept until you delete "
            + "them."
    }

    /// The Monthly Backups stepper's value: "12 Months", "1 Month" or "Off" (L11).
    public func monthlyValue(_ months: Int) -> String {
        switch months {
        case 0: Self.monthlyOff
        case 1: "1 Month"
        default: "\(months) Months"
        }
    }

    /// 'Delete 4 Backups?' or 'Delete 1 Backup?' (L12, L14).
    public func pruneTitle(_ count: Int) -> String {
        "\(pruneConfirm(count))?"
    }

    /// The destructive button: 'Delete 4 Backups' or 'Delete 1 Backup' (L12, L14).
    public func pruneConfirm(_ count: Int) -> String {
        count == 1 ? "Delete 1 Backup" : "Delete \(count) Backups"
    }

    public func pruneMessage(_ count: Int) -> String {
        let them = count == 1 ? "deletes 1 of them" : "deletes \(count) of them"
        return "Keeping fewer automatic backups \(them) now. Manual and Before restore backups aren’t affected."
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

    public var advancedFooter: String {
        "Automatic daily backups, Back Up Now, export and restore. Backups stay on this \(deviceName)."
    }

    /// The Delete footnote on every backup's detail, naming the device's biometry, then the Keep footer (D116.1,
    /// D196.1, L25): "Any backup can be deleted. Delete asks you to confirm, and asks for Face ID or the app
    /// passcode first when App Lock is on. little-orbit keeps your 7 most recent automatic backups…"
    public func deleteFootnote(_ method: AppUnlockMethod) -> String {
        let unlock =
            switch method {
            case .faceID: "Face ID or the app passcode"
            case .touchID: "Touch ID or the app passcode"
            case .opticID: "Optic ID or the app passcode"
            case .passcodeOnly: "the app passcode"
            }
        return "Any backup can be deleted. Delete asks you to confirm, and asks for \(unlock) first when App Lock is "
            + "on. \(keepFooter)"
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

    /// "Version 1" in the iOS backup detail; the list line keeps "Format 1" (frame 165:504). "Unknown" when the
    /// manifest was never read.
    public static func version(_ version: Int) -> String {
        version > 0 ? "Version \(version)" : unknownKind
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

    public static func kind(_ kind: BackupKind?) -> String {
        switch kind {
        case .automatic: "Automatic"
        case .manual: "Manual"
        case .beforeRestore: "Before restore"
        case nil: unknownKind
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
        version > 0 ? "Format \(version)" : "Format \(unknownKind.lowercased())"
    }

    /// The Export sheet's summary of the selected backup, on iOS and macOS (R1, S64, S76, D186).
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
        let status: String? =
            switch record.condition {
            case .restorable: nil
            case .damaged: Self.damagedLabel
            case .newerFormat: Self.newerFormatNote
            }
        let explanation: String? =
            switch record.condition {
            case .restorable: nil
            case .damaged: Self.damagedExplanation
            case .newerFormat: "\(Self.newerFormatNote) \(Self.newerFormatDetail)"
            }
        return BackupRowModel(
            id: record.id,
            kind: record.kind,
            title: title,
            kindText: kind,
            sizeText: sizeText,
            formatText: Self.format(record.formatVersion),
            countsText: countsText,
            detailLine: [kind, sizeText, Self.format(record.formatVersion)].joined(separator: " · "),
            accessibilityLabel: ([title, "\(kind) backup"] + (status.map { [$0] } ?? []) + [
                sizeText, countsText.replacingOccurrences(of: " · ", with: ", "),
            ])
            .joined(separator: ", "),
            accountCount: record.accountCount,
            transactionCount: record.transactionCount,
            attachmentCount: record.attachmentCount,
            formatVersion: record.formatVersion,
            condition: record.condition,
            statusText: status,
            explanation: explanation,
        )
    }
}

/// One backup in the list and its detail. Never carries an amount.
public struct BackupRowModel: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: BackupKind?
    /// "Today, 9:12 AM".
    public var title: String
    public var kindText: String
    public var sizeText: String
    public var formatText: String
    /// "5 accounts · 120 transactions".
    public var countsText: String
    /// "Automatic · 1.8 MB · Format 1".
    public var detailLine: String
    /// "Today, 9:12 AM, Automatic backup, 1.8 MB, 5 accounts, 120 transactions" (S35), with "Damaged" or the
    /// newer-format note after the kind (L29, L35).
    public var accessibilityLabel: String
    public var accountCount: Int
    public var transactionCount: Int
    /// The detail hides its Attachments row when this is 0 (S61, S72).
    public var attachmentCount: Int
    public var formatVersion: Int
    public var condition: BackupCondition
    /// 'Damaged' or "Made by a newer version of little-orbit.", shown in the list (L29, L35). `nil` when restorable.
    public var statusText: String?
    /// The detail's explanation of why Restore… and Export… are unavailable (D196.3, D197.2).
    public var explanation: String?

    /// Restore… and Export… are available. A damaged or newer-format backup can still be deleted (L29, L35, L43).
    public var canRestore: Bool {
        condition == .restorable
    }
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
