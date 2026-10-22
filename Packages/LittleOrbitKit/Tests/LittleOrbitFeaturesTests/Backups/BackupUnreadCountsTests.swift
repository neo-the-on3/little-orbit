import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// UI Designer, comment 6353639065: a count that couldn't be read is never shown, because a "0" reads as real
/// data. A damaged backup that was never read and a newer-format one have no counts line in the iOS list, empty
/// Accounts and Transactions cells on macOS, no counts in the VoiceOver label, and D200.1's "Unknown" in the iOS
/// detail with no Attachments row. Counts that were read show as before, a damaged backup's from its last good read
/// too (D202.1).
@MainActor
@Suite("Backup counts that weren't read are never shown", .timeLimit(.minutes(2)))
struct BackupUnreadCountsTests {
    private let presentation = BackupPresentation(
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "Asia/Kolkata") ?? .gmt,
        device: .iPhone,
    )
    private let now = Date(timeIntervalSince1970: 1_792_640_525)

    /// Nothing about the counts anywhere in the row: list, macOS cells, VoiceOver, iOS detail.
    private func expectNoCounts(_ row: BackupRowModel) {
        #expect(row.countsText == nil)
        #expect(row.accountsText == nil)
        #expect(row.transactionsText == nil)
        #expect(!row.accessibilityLabel.contains("account"))
        #expect(!row.accessibilityLabel.contains("transaction"))
        #expect(row.detailAccountsText == "Unknown")
        #expect(row.detailTransactionsText == "Unknown")
        #expect(row.attachmentsText == nil)
    }

    private func unread(_ condition: BackupCondition, kind: BackupKind?, version: Int) -> BackupRecord {
        BackupRecord(
            kind: kind,
            createdAt: now,
            formatVersion: version,
            byteSize: 2_400,
            accountCount: nil,
            transactionCount: nil,
            attachmentCount: nil,
            condition: condition,
        )
    }

    @Test("Damaged and never read: no counts line, empty cells, none in VoiceOver, Unknown in the detail")
    func damagedNeverRead() {
        let row = presentation.row(unread(.damaged, kind: nil, version: 0), now: now)
        expectNoCounts(row)
        #expect(row.statusText == "Damaged")
        #expect(row.accessibilityLabel.contains("Damaged"))
    }

    @Test("Newer format: the same, with its note")
    func newerFormat() {
        let row = presentation.row(unread(.newerFormat, kind: .manual, version: 2), now: now)
        expectNoCounts(row)
        #expect(row.statusText == "Made by a newer version of little-orbit.")
    }

    @Test("Damaged but read before: the counts from that read show, attachments too (D202.1)")
    func damagedReadBefore() {
        let record = BackupRecord(
            kind: .automatic,
            createdAt: now,
            byteSize: 2_400,
            accountCount: 5,
            transactionCount: 1_200,
            attachmentCount: 2,
            condition: .damaged,
        )
        let row = presentation.row(record, now: now)
        #expect(row.countsText == "5 accounts · 1,200 transactions")
        #expect(row.accountsText == "5")
        #expect(row.transactionsText == "1,200")
        #expect(row.accessibilityLabel.hasSuffix("5 accounts, 1,200 transactions"))
        #expect(row.detailAccountsText == "5")
        #expect(row.detailTransactionsText == "1,200")
        #expect(row.attachmentsText == "2")
    }

    @Test("Restorable: counts show, 0 included since it was read; no Attachments row at 0")
    func restorable() {
        let record = BackupRecord(
            kind: .manual,
            createdAt: now,
            byteSize: 2_400,
            accountCount: 0,
            transactionCount: 1,
            attachmentCount: 0,
        )
        let row = presentation.row(record, now: now)
        #expect(row.countsText == "0 accounts · 1 transaction")
        #expect(row.accountsText == "0")
        #expect(row.transactionsText == "1")
        #expect(row.accessibilityLabel.hasSuffix("0 accounts, 1 transaction"))
        #expect(row.detailAccountsText == "0")
        #expect(row.detailTransactionsText == "1")
        #expect(row.attachmentsText == nil)
    }

    @Test("The list marks counts as not read only where no manifest was read: never read, newer format")
    func listedCounts() async throws {
        let harness = try BackupHarness()
        let good = try await harness.service.backUpNow()
        harness.advance(60)
        let damaged = try await harness.service.backUpNow()
        harness.advance(60)
        let newer = try await harness.service.backUpNow()
        _ = try await harness.service.overview()

        // Read before, then its manifest goes: damaged, with the counts from that read.
        try FileManager.default.removeItem(
            at: harness.backupFolder(damaged.id).appendingPathComponent(BackupFormat.manifestPath)
        )
        // A newer format's manifest: its counts aren't read, even though an earlier read had some.
        let manifestURL = harness.backupFolder(newer.id).appendingPathComponent(BackupFormat.manifestPath)
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        object["formatVersion"] = 2
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: manifestURL)
        // A folder no list has seen, with no manifest: damaged and never read.
        let stray = UUID()
        let strayURL = harness.backupFolder(good.id).deletingLastPathComponent()
            .appendingPathComponent(stray.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: strayURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: strayURL.appendingPathComponent("shared.json"))

        let backups = Dictionary(
            uniqueKeysWithValues: try await harness.service.overview().backups.map { ($0.id, $0) }
        )
        let goodRecord = try #require(backups[good.id])
        #expect(goodRecord.condition == .restorable)
        #expect(goodRecord.accountCount == good.accountCount)
        #expect(goodRecord.accountCount != nil)

        let damagedRecord = try #require(backups[damaged.id])
        #expect(damagedRecord.condition == .damaged)
        #expect(damagedRecord.accountCount == damaged.accountCount)
        #expect(damagedRecord.transactionCount == damaged.transactionCount)
        #expect(damagedRecord.accountCount != nil)

        let newerRecord = try #require(backups[newer.id])
        #expect(newerRecord.condition == .newerFormat)
        #expect(newerRecord.accountCount == nil)
        #expect(newerRecord.transactionCount == nil)
        #expect(newerRecord.attachmentCount == nil)

        let strayRecord = try #require(backups[stray])
        #expect(strayRecord.condition == .damaged)
        #expect(strayRecord.accountCount == nil)
        #expect(strayRecord.transactionCount == nil)
        #expect(strayRecord.attachmentCount == nil)
    }
}
