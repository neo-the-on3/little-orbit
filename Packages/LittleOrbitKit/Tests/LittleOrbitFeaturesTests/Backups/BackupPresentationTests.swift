import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The Backups copy (D118.4, D173.10, UI Designer). Buttons and titles are title case; body text is sentence case.
@Suite("Backup presentation")
struct BackupPresentationTests {
    private let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
    private var presentation: BackupPresentation {
        BackupPresentation(locale: Locale(identifier: "en_US"), timeZone: zone, device: .iPhone)
    }

    private let now = Date(timeIntervalSince1970: 1_792_640_525)

    @Test("Buttons and titles are title case (D173.10)")
    func titleCase() {
        #expect(BackupPresentation.backUpNow == "Back Up Now")
        #expect(BackupPresentation.restoreFromFile == "Restore from File…")
        #expect(BackupPresentation.restoreFromBackupMenu == "Restore from Backup…")
        #expect(BackupPresentation.deleteBackup == "Delete Backup")
        #expect(BackupPresentation.damagedTitle == "This Backup Is Damaged")
        #expect(BackupPresentation.newerFormatTitle == "Update little-orbit to Restore This Backup")
        #expect(BackupPresentation.restoreTitle == "Restore This Backup?")
        #expect(BackupPresentation.emptyTitle == "No Backups Yet")
    }

    @Test("Dates read Today, Yesterday, then the day, in the current time zone")
    func dates() {
        #expect(spaced(presentation.date(now, now: now)) == "Today, 9:12 AM")
        #expect(spaced(presentation.date(now - 86_400, now: now)) == "Yesterday, 9:12 AM")
        #expect(spaced(presentation.date(now - 3 * 86_400, now: now)) == "Oct 19, 2026, 9:12 AM")
    }

    @Test("Rows show kind, size and format; counts and no amounts (D62)")
    func row() {
        let record = BackupRecord(
            kind: .automatic,
            createdAt: now,
            byteSize: 1_800_000,
            accountCount: 5,
            transactionCount: 120,
        )
        let row = presentation.row(record, now: now)
        #expect(row.kindText == "Automatic")
        #expect(row.formatText == "Format 1")
        #expect(row.countsText == "5 accounts · 120 transactions")
        #expect(row.detailLine.hasPrefix("Automatic · "))
        #expect(row.detailLine.hasSuffix(" · Format 1"))
        #expect(row.attachmentCount == 0)
    }

    @Test("Singular counts")
    func singular() {
        #expect(presentation.counts(1, 1) == "1 account · 1 transaction")
    }

    @Test("The macOS export summary adds attachments only when there are some")
    func exportSummary() {
        let plain = BackupRecord(kind: .manual, createdAt: now, accountCount: 2, transactionCount: 3)
        #expect(!presentation.exportSummary(plain, now: now).contains("attachment"))
        var with = plain
        with.attachmentCount = 2
        #expect(presentation.exportSummary(with, now: now).hasSuffix("· 2 attachments"))
    }

    @Test("Device-specific copy names the device")
    func device() {
        #expect(presentation.deleteMessage == "It’s removed from this iPhone. This can’t be undone.")
        #expect(presentation.notEnoughStorageMessage.contains("No older backup was removed."))
        #expect(presentation.notEnoughStorageMessage.contains("then tap Back Up Now"))
    }

    private func presentation(_ device: BackupDevice, zone: TimeZone? = nil) -> BackupPresentation {
        BackupPresentation(locale: Locale(identifier: "en_US"), timeZone: zone ?? self.zone, device: device)
    }

    @Test("The export name uses the creation time in the current time zone, 24-hour, no seconds (S59)")
    func fileName() {
        let record = BackupRecord(kind: .manual, createdAt: now, nameIndex: 1)
        #expect(presentation.fileName(for: record) == "little-orbit 2026-10-22 0912.littleorbit-backup")
        let afternoon = BackupRecord(kind: .manual, createdAt: now + 8 * 3_600, nameIndex: 1)
        #expect(presentation.fileName(for: afternoon) == "little-orbit 2026-10-22 1712.littleorbit-backup")
    }

    @Test("The stored index adds ' 2', and the time follows the zone at export (D133, D173.11, S71, S80)")
    func fileNameSuffixAndZone() {
        let london = TimeZone(identifier: "Europe/London") ?? .gmt
        let second = BackupRecord(kind: .manual, createdAt: now + 10, nameIndex: 2)
        #expect(presentation.fileName(for: second) == "little-orbit 2026-10-22 0912 2.littleorbit-backup")
        #expect(
            presentation(.iPhone, zone: london).fileName(for: second)
                == "little-orbit 2026-10-22 0442 2.littleorbit-backup"
        )
    }

    @Test("Every detail's footnote is the D196.1 string, with the device's biometry and the settings (L25)")
    func deleteFootnotes() {
        #expect(
            presentation.deleteFootnote(.faceID)
                == "Any backup can be deleted. Delete asks you to confirm, and asks for Face ID or the app passcode "
                + "first when App Lock is on. little-orbit keeps your 7 most recent automatic backups and the first "
                + "automatic backup of each month for 12 months. Manual and Before restore backups are kept until "
                + "you delete them."
        )
        #expect(presentation.deleteFootnote(.touchID).contains("asks for Touch ID or the app passcode first"))
        #expect(presentation.deleteFootnote(.passcodeOnly).contains("asks for the app passcode first when"))
        var custom = presentation
        custom.retention = BackupRetention(recentAutomatic: 3, monthlyMonths: 0)
        let footnote = custom.deleteFootnote(.faceID)
        #expect(
            footnote.hasSuffix(
                "little-orbit keeps your 3 most recent automatic backups. Manual and Before restore "
                    + "backups are kept until you delete them."
            )
        )
        for text in [footnote, presentation.deleteFootnote(.opticID)] {
            #expect(!text.contains("Otherwise"))
            #expect(!text.contains("14"))
        }
    }

    @Test("Damaged and newer-format rows say so, in the list, the detail and VoiceOver (L29, L35)")
    func conditionRows() {
        let now = Date(timeIntervalSince1970: 1_792_640_525)
        let damaged = presentation.row(
            BackupRecord(kind: .automatic, createdAt: now, condition: .damaged),
            now: now,
        )
        #expect(damaged.statusText == "Damaged")
        #expect(
            damaged.explanation
                == "This backup is damaged and can’t be restored. Some of its files are missing or have changed."
        )
        #expect(damaged.accessibilityLabel.contains("Automatic backup, Damaged"))
        #expect(!damaged.canRestore)
        let newer = presentation.row(
            BackupRecord(kind: .manual, createdAt: now, formatVersion: 2, condition: .newerFormat),
            now: now,
        )
        #expect(newer.statusText == "Made by a newer version of little-orbit.")
        #expect(newer.explanation == "Made by a newer version of little-orbit. Update little-orbit to restore it.")
        #expect(!newer.accessibilityLabel.contains("Damaged"))
        #expect(!newer.canRestore)
        let fine = presentation.row(BackupRecord(kind: .manual, createdAt: now), now: now)
        #expect(fine.statusText == nil)
        #expect(fine.canRestore)
        let unknown = presentation.row(
            BackupRecord(kind: nil, createdAt: now, formatVersion: 0, condition: .damaged),
            now: now,
        )
        #expect(unknown.kindText == "Unknown")
        #expect(unknown.formatText == "Format unknown")
    }

    @Test("The alert strings are unchanged (D197a.3)")
    func alertStrings() {
        #expect(BackupPresentation.newerFormatTitle == "Update little-orbit to Restore This Backup")
        #expect(
            BackupPresentation.newerFormatMessage
                == "This backup was made with a newer version of little-orbit. Your data hasn’t changed."
        )
        #expect(BackupPresentation.damagedTitle == "This Backup Is Damaged")
        #expect(BackupPresentation.damagedMessage == "It can’t be restored. Your data hasn’t changed.")
    }

    @Test("Couldn’t Restore and Couldn’t Open Backup are Product Manager's copy, with curly apostrophes (D207)")
    func d207Strings() {
        #expect(BackupAlert.beforeRestoreFailed.title == "Couldn’t Restore")
        #expect(
            BackupAlert.beforeRestoreFailed.message
                == "little-orbit couldn’t make a safe copy of your current data first, so nothing was replaced. "
                + "Your data hasn’t changed."
        )
        #expect(BackupAlert.unreadableFile.title == "Couldn’t Open Backup")
        #expect(
            BackupAlert.unreadableFile.message
                == "The file couldn’t be read. Make sure it’s fully downloaded and try again. Your data hasn’t changed."
        )
        for alert in [BackupAlert.beforeRestoreFailed, .unreadableFile] {
            #expect(!(alert.title + alert.message).contains("'"))
        }
    }

    @Test("macOS copy: click, the Mac empty state and the inline restore line (UI Designer)")
    func macCopy() {
        let mac = presentation(.mac)
        #expect(mac.notEnoughStorageMessage.contains("Free up space on this Mac, then click Back Up Now."))
        #expect(presentation(.iPhone).notEnoughStorageMessage.contains("then tap Back Up Now."))
        for copy in [mac.notEnoughStorageMessage, mac.emptyMessage, mac.storageFooter, mac.retentionNote] {
            #expect(!copy.contains(" tap "))
        }
        #expect(
            mac.emptyMessage
                == "The first automatic backup is made after you change something. You can also back up now or "
                + "restore from a backup file."
        )
        let before = BackupRecord(kind: .beforeRestore, createdAt: now)
        #expect(
            spaced(mac.restoredMessage(before: before, now: now))
                == "Backup restored. Your previous data is saved as a Before restore backup (Today, 9:12 AM)."
        )
        #expect(mac.storageFooter.contains("inside little-orbit’s own container"))
        #expect(!presentation.storageFooter.contains("container"))
    }

    @Test("Restore steps and the detail's Version row (UI Designer)")
    func stepsAndVersion() {
        #expect(BackupPresentation.fraction(.savingCurrentData) < BackupPresentation.fraction(.replacingData))
        #expect(BackupPresentation.fraction(.finished) == 1)
        #expect(BackupPresentation.savedCurrentDataStep == "Current data saved as a Before restore backup")
        #expect(BackupPresentation.replacingDataStep == "Replacing data…")
        #expect(BackupPresentation.version(1) == "Version 1")
        #expect(BackupPresentation.format(1) == "Format 1")
        #expect(BackupPresentation.detailTitle == "Backup")
    }

    @Test("The Export sheet's note and buttons (D182.4, R1, UI Designer 277:4915 / 277:4581)")
    func exportNote() {
        #expect(
            BackupPresentation.unencryptedWarning == "This file isn’t encrypted and contains all your financial data."
        )
        #expect(BackupPresentation.exportConfirm == "Export")
        #expect(BackupPresentation.exportEllipsis == "Export…")
        #expect(BackupPresentation.exportTitle == "Export Backup")
        #expect(BackupPresentation.unencryptedWarningSymbol == "exclamationmark.triangle.fill")
        #expect(BackupPresentation.warning == "Warning")
        #expect(
            BackupPresentation.unencryptedWarningAccessibilityLabel
                == "Warning, This file isn’t encrypted and contains all your financial data."
        )
    }

    @Test("The Export summary matches the frames, with singular and plural counts (D186)")
    func exportSummaryFormat() {
        let automatic = BackupRecord(kind: .automatic, createdAt: now, accountCount: 5, transactionCount: 120)
        #expect(
            spaced(presentation.exportSummary(automatic, now: now))
                == "Backup from Today, 9:12 AM · Automatic · 5 accounts · 120 transactions"
        )
        let single = BackupRecord(
            kind: .manual,
            createdAt: now,
            accountCount: 1,
            transactionCount: 1,
            attachmentCount: 1,
        )
        #expect(
            spaced(presentation.exportSummary(single, now: now))
                == "Backup from Today, 9:12 AM · Manual · 1 account · 1 transaction · 1 attachment"
        )
        let empty = BackupRecord(kind: .manual, createdAt: now, accountCount: 0, transactionCount: 0)
        #expect(
            spaced(presentation.exportSummary(empty, now: now)).hasSuffix("· Manual · 0 accounts · 0 transactions")
        )
    }

    @Test("The Keep footer follows N and M, with Monthly Backups off and singulars (L11)")
    func keepFooter() {
        var copy = presentation
        #expect(
            copy.keepFooter
                == "little-orbit keeps your 7 most recent automatic backups and the first automatic backup of each "
                + "month for 12 months. Manual and Before restore backups are kept until you delete them."
        )
        copy.retention = BackupRetention(recentAutomatic: 7, monthlyMonths: 0)
        #expect(
            copy.keepFooter
                == "little-orbit keeps your 7 most recent automatic backups. Manual and Before restore backups are "
                + "kept until you delete them."
        )
        copy.retention = BackupRetention(recentAutomatic: 1, monthlyMonths: 1)
        #expect(copy.keepFooter.hasPrefix("little-orbit keeps your most recent automatic backup and the first"))
        #expect(!copy.keepFooter.contains("14"))
        #expect(!copy.retentionNote.contains("14"))
        #expect(!copy.emptyMessage.contains("14"))
    }

    @Test("Monthly Backups shows Off for 0, and months otherwise (L11)")
    func monthlyValue() {
        #expect(presentation.monthlyValue(0) == "Off")
        #expect(presentation.monthlyValue(1) == "1 Month")
        #expect(presentation.monthlyValue(12) == "12 Months")
    }

    @Test("The lowering alert has the exact count, singular for one (L12, L14)")
    func pruneAlert() {
        #expect(presentation.pruneTitle(4) == "Delete 4 Backups?")
        #expect(presentation.pruneConfirm(4) == "Delete 4 Backups")
        #expect(
            presentation.pruneMessage(4)
                == "Keeping fewer automatic backups deletes 4 of them now. Manual and Before restore backups "
                + "aren’t affected."
        )
        #expect(presentation.pruneTitle(1) == "Delete 1 Backup?")
        #expect(presentation.pruneConfirm(1) == "Delete 1 Backup")
        #expect(presentation.pruneMessage(1).hasPrefix("Keeping fewer automatic backups deletes 1 of them now."))
    }
}
