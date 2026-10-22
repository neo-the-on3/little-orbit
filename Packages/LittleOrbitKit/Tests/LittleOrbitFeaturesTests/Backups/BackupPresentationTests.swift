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

    @Test("The Delete footnote has the retention sentence only for automatic backups (UI Designer, 165:599)")
    func deleteFootnotes() {
        #expect(
            presentation.deleteFootnote(.faceID, kind: .manual)
                == "Manual and Before restore backups stay until you delete them. With App Lock on, Delete asks "
                + "for Face ID or the app passcode first."
        )
        #expect(
            presentation.deleteFootnote(.passcodeOnly, kind: .beforeRestore)
                .hasSuffix("asks for the app passcode first.")
        )
        let automatic = presentation.deleteFootnote(.touchID, kind: .automatic)
        #expect(automatic.hasPrefix("little-orbit keeps the 14 most recent automatic backups."))
        #expect(automatic.contains("Touch ID or the app passcode"))
    }

    @Test("macOS copy: click, the Mac empty state and the inline restore line (UI Designer)")
    func macCopy() {
        let mac = presentation(.mac)
        #expect(mac.notEnoughStorageMessage.contains("Free up space on this Mac, then click Back Up Now."))
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

    @Test("Retention copy follows the policy constant")
    func retention() {
        #expect(presentation.retentionNote.contains("keeps the \(BackupPolicy.automaticRetention) most recent"))
    }
}
