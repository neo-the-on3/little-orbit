import Foundation
import LittleOrbitDomain

/// Copy and formatting for the Backups screens (#40), shared by iOS and macOS. Titles and buttons use title case;
/// body text, messages and footnotes use sentence case (D118.4, D173.10). No amount is ever shown (D62).
///
/// Every sentence is one whole entry in the String Catalog (`Resources/Localizable.xcstrings`), read through
/// `FeatureText`, with positional arguments and catalog plurals where a translation needs them. The English text
/// is Product Manager's wording.
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

    // MARK: Buttons and titles (D173.10)

    public static let backUpNow = FeatureText.format("Back Up Now")
    public static let restoreFromFile = FeatureText.format("Restore from File…")
    public static let restoreFromBackupMenu = FeatureText.format("Restore from Backup…")
    public static let restoreEllipsis = FeatureText.format("Restore…")
    public static let exportEllipsis = FeatureText.format("Export…")
    /// The iOS Export sheet's navigation-bar button: no ellipsis, since the share sheet follows directly
    /// (UI Designer, frame 277:4915). macOS keeps "Export…" (277:4581).
    public static let exportConfirm = FeatureText.format("Export")
    public static let deleteBackup = FeatureText.format("Delete Backup")
    public static let deleteEllipsis = FeatureText.format("Delete…")
    public static let backupInProgress = FeatureText.format("Backup in progress…")
    /// VoiceOver announcements for Back Up Now (D179.2, UI Designer). A full disk announces
    /// `notEnoughStorageMessage` instead of the finish.
    public static let backupStartedAnnouncement = FeatureText.format("Backup in progress")
    public static let backupFinishedAnnouncement = FeatureText.format("Backup complete")
    public static let backupFailedAnnouncement = FeatureText.format("Backup failed")
    /// The iOS backup detail's title; the date is in its Date row (UI Designer, frame 165:504).
    public static let detailTitle = FeatureText.format("Backup")
    /// The restore steps under the progress bar (UI Designer, frames 165:1028 and 169:5070).
    public static let savedCurrentDataStep = FeatureText.format("Current data saved as a Before restore backup")
    public static let replacingDataStep = FeatureText.format("Replacing data…")
    /// Exported file names start with this (D116.4).
    public static let fileNamePrefix = "little-orbit"
    public static let damagedTitle = FeatureText.format("This Backup Is Damaged")
    public static let damagedMessage = FeatureText.format("It can’t be restored. Your data hasn’t changed.")
    public static let newerFormatTitle = FeatureText.format("Update little-orbit to Restore This Backup")
    public static let newerFormatMessage = FeatureText.format(
        """
        This backup was made with a newer version of little-orbit. Your data hasn’t changed.
        """
    )
    public static let restoreTitle = FeatureText.format("Restore This Backup?")
    public static let restoringTitle = FeatureText.format("Restoring Backup")
    public static let restoredToast = FeatureText.format("Backup restored · Before restore backup saved")
    public static let deleteTitle = FeatureText.format("Delete This Backup?")
    public static let emptyTitle = FeatureText.format("No Backups Yet")
    public static let exportTitle = FeatureText.format("Export Backup")
    /// The retention section (L11): standard Stepper rows, as UI Designer approved.
    public static let keepHeader = FeatureText.format("Keep")
    public static let recentAutomaticBackups = FeatureText.format("Recent Automatic Backups")
    public static let monthlyBackups = FeatureText.format("Monthly Backups")
    public static let monthlyOff = FeatureText.format("Off")
    /// A damaged backup in the list and its detail (D196.3, L29).
    public static let damagedLabel = FeatureText.format("Damaged")
    public static let damagedExplanation = FeatureText.format(
        """
        This backup is damaged and can’t be restored. Some of its files are missing or have changed.
        """
    )
    /// A newer-format backup in the list, and the line its detail adds (D197.2, L35).
    public static let newerFormatNote = FeatureText.format("Made by a newer version of little-orbit.")
    public static let newerFormatDetail = FeatureText.format("Update little-orbit to restore it.")
    /// The kind of a damaged folder whose manifest was never read.
    public static let unknownKind = FeatureText.format("Unknown")
    /// The Export sheet's one line, on every export (D182.4).
    public static let unencryptedWarning = FeatureText.format(
        """
        This file isn’t encrypted and contains all your financial data.
        """
    )
    /// The note's SF Symbol, shown in the warning colour (UI Designer, frames 277:4915 and 277:4581).
    public static let unencryptedWarningSymbol = "exclamationmark.triangle.fill"
    /// What VoiceOver says for the warning icon, before the note.
    public static let warning = FeatureText.format("Warning")
    /// The note as one VoiceOver element: "Warning, This file isn’t encrypted and contains all your financial
    /// data." (UI Designer, after Tester's 6335997896.)
    public static let unencryptedWarningAccessibilityLabel = FeatureText.format(
        """
        Warning, This file isn’t encrypted and contains all your financial data.
        """
    )
    public static let restoreInterruptedNote = FeatureText.format(
        """
        Keep little-orbit open. If the restore is interrupted, your data stays exactly as it was before.
        """
    )

    /// The macOS tab's inline line after a restore (UI Designer, frame 169:5253). iOS shows `restoredToast`.
    public func restoredMessage(before: BackupRecord, now: Date) -> String {
        FeatureText.format(
            "Backup restored. Your previous data is saved as a Before restore backup (%@).",
            date(before.createdAt, now: now),
        )
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
        version > 0 ? FeatureText.format("Version %lld", version) : unknownKind
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    public func restoreMessage(for manifest: BackupManifest, now: Date) -> String {
        let summary = [date(manifest.createdAt, now: now), counts(manifest.accountCount, manifest.transactionCount)]
            .joined(separator: " · ")
        return FeatureText.format(
            """
            All data on this %1$@ will be replaced with this backup (%2$@). Your current data is saved first \
            as a Before restore backup, so you can go back. App Lock, Hide amounts, report exclusions and \
            theme on this %1$@ don’t change.
            """,
            deviceName,
            summary,
        )
    }

    // MARK: Values

    public static func kind(_ kind: BackupKind?) -> String {
        switch kind {
        case .automatic: FeatureText.format("Automatic")
        case .manual: FeatureText.format("Manual")
        case .beforeRestore: FeatureText.format("Before restore")
        case nil: unknownKind
        }
    }

    /// "Automatic backup", as VoiceOver reads a row's kind.
    static func kindBackup(_ kind: BackupKind?) -> String {
        switch kind {
        case .automatic: FeatureText.format("Automatic backup")
        case .manual: FeatureText.format("Manual backup")
        case .beforeRestore: FeatureText.format("Before restore backup")
        case nil: FeatureText.format("Unknown backup")
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
            return FeatureText.format("Today, %@", time)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return FeatureText.format("Yesterday, %@", time)
        }
        let day = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).day().month(.abbreviated).year()
        )
        return FeatureText.format("%1$@, %2$@", day, time)
    }

    /// The stored file's size, attachments included (D116.5), formatted for the locale.
    public func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    public func counts(_ accounts: Int, _ transactions: Int) -> String {
        FeatureText.format(
            "%1$@ · %2$@",
            FeatureText.plural("%lld accounts", one: "%lld account", accounts),
            FeatureText.plural("%lld transactions", one: "%lld transaction", transactions),
        )
    }

    public static func format(_ version: Int) -> String {
        version > 0 ? FeatureText.format("Format %lld", version) : FeatureText.format("Format unknown")
    }

    /// The Export sheet's summary of the selected backup, on iOS and macOS (R1, S64, S76, D186).
    public func exportSummary(_ record: BackupRecord, now: Date) -> String {
        var parts = [
            FeatureText.format("Backup from %@", date(record.createdAt, now: now)),
            Self.kind(record.kind),
            FeatureText.plural("%lld accounts", one: "%lld account", record.accountCount),
            FeatureText.plural("%lld transactions", one: "%lld transaction", record.transactionCount),
        ]
        if record.attachmentCount > 0 {
            parts.append(FeatureText.plural("%lld attachments", one: "%lld attachment", record.attachmentCount))
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
            case .newerFormat: FeatureText.format("%1$@ %2$@", Self.newerFormatNote, Self.newerFormatDetail)
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
            accessibilityLabel: ([title, Self.kindBackup(record.kind)] + (status.map { [$0] } ?? []) + [
                sizeText,
                FeatureText.format(
                    "%1$@, %2$@",
                    FeatureText.plural("%lld accounts", one: "%lld account", record.accountCount),
                    FeatureText.plural("%lld transactions", one: "%lld transaction", record.transactionCount),
                ),
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
