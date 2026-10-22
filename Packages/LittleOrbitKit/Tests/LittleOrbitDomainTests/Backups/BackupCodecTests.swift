import Foundation
import LittleOrbitDomain
import Testing

/// D63, D96.1, D116.4, D182 and Kiran's backup layout: each backup is a self-contained folder, plain in format 1.
@Suite("Backup codec")
struct BackupCodecTests {
    private let codec = BackupCodec(hashing: FakeBackupHashing())
    private let created = Date(timeIntervalSince1970: 1_792_640_525.123_456)
    private let kolkata = "Asia/Kolkata"
    /// 2025-03-10 12:00 UTC.
    private let lastYear = Date(timeIntervalSince1970: 1_741_608_000)

    private let dinar = Account(
        name: "Kuwait Account",
        type: .savings,
        currencyCode: "KWD",
        openingBalance: Decimal(string: "1.234", locale: Locale(identifier: "en_US_POSIX")) ?? 0,
        sortOrder: 1,
    )
    private let cash = Account(name: "Wallet", type: .cash, currencyCode: "INR", openingBalance: 500, sortOrder: 2)

    private var sample = LedgerSnapshot()

    init() {
        sample = makeLedger()
    }

    private func ledger() -> LedgerSnapshot {
        sample
    }

    private func makeLedger() -> LedgerSnapshot {
        let spend = Transaction(
            amount: 120,
            date: created,
            timeZoneID: kolkata,
            accountID: cash.id,
            createdAt: created,
        )
        let older = Transaction(amount: 40, date: lastYear, timeZoneID: kolkata, accountID: cash.id)
        let deleted = Transaction(
            amount: 7,
            date: lastYear,
            timeZoneID: kolkata,
            accountID: dinar.id,
            deletedAt: created,
        )
        let transfer = Transaction(
            type: .transfer,
            amount: 1,
            date: lastYear,
            timeZoneID: kolkata,
            accountID: dinar.id,
            transferAccountID: cash.id,
            destinationAmount: 270,
        )
        let split = TransactionSplit(transactionID: spend.id, amount: 20, createdAt: created)
        let receipt = Attachment(
            transactionID: spend.id,
            fileName: "Receipt.jpg",
            contentType: "image/jpeg",
            byteSize: 4,
            data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            createdAt: created,
        )
        return LedgerSnapshot(
            accounts: [dinar, cash],
            transactions: [spend, older, deleted, transfer],
            categories: [TransactionCategory(name: "Groceries")],
            payees: [Payee(name: "Corner Shop")],
            splits: [split],
            attachments: [receipt],
        )
    }

    private func contents(_ ledger: LedgerSnapshot? = nil) -> BackupContents {
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: 2,
            transactionCount: 3,
            attachmentCount: 1,
        )
        return BackupContents(manifest: manifest, ledger: ledger ?? self.ledger())
    }

    @Test("A backup round-trips exactly, including KWD 1.234, sub-second dates and deleted records")
    func roundTrip() throws {
        let original = contents()
        let decoded = try codec.decode(codec.encode(original))
        #expect(decoded == original)
        #expect(decoded.accounts.first { $0.currencyCode == "KWD" }?.openingBalance.description == "1.234")
        #expect(decoded.manifest.createdAt == created)
        #expect(decoded.transactions.contains { $0.deletedAt != nil })
        #expect(decoded.attachments.first?.data == Data([0xFF, 0xD8, 0xFF, 0xE0]))
    }

    @Test(
        "The folder holds manifest.json, shared.json, transfers/<year>.json, accounts/<id>/<year>.json and attachments"
    )
    func layout() throws {
        let files = try codec.encode(contents())
        let receipt = try #require(ledger().attachments.first)
        #expect(
            Set(files.paths) == [
                "manifest.json",
                "shared.json",
                "transfers/2025.json",
                "accounts/\(cash.id.uuidString)/2025.json",
                "accounts/\(cash.id.uuidString)/2026.json",
                "accounts/\(dinar.id.uuidString)/2025.json",
                "attachments/\(receipt.id.uuidString)",
            ]
        )
        #expect(files["attachments/\(receipt.id.uuidString)"] == receipt.data)
        let shared = try #require(files["shared.json"].flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(shared.contains("Kuwait Account"))
        #expect(shared.contains("Groceries"))
        let year = try #require(files["accounts/\(cash.id.uuidString)/2026.json"])
        let object = try #require(JSONSerialization.jsonObject(with: year) as? [String: Any])
        #expect(Set(object.keys) == ["transactions", "splits", "attachments"])
        // The attachment's bytes are only in attachments/, never inside the JSON.
        #expect(String(bytes: year, encoding: .utf8)?.contains("Receipt.jpg") == true)
        #expect((object["attachments"] as? [[String: Any]])?.first?["data"] == nil)
    }

    @Test("A transaction's year is its own local year, not UTC's")
    func localYear() throws {
        // 2026-01-01 00:30 IST is still 2025 in UTC.
        let newYear = Date(timeIntervalSince1970: 1_767_205_800)
        let spend = Transaction(amount: 5, date: newYear, timeZoneID: kolkata, accountID: cash.id)
        let files = try codec.encode(contents(LedgerSnapshot(accounts: [cash], transactions: [spend])))
        #expect(files.paths.contains("accounts/\(cash.id.uuidString)/2026.json"))
        #expect(!files.paths.contains("accounts/\(cash.id.uuidString)/2025.json"))
    }

    @Test("Records with no account or no transaction are kept in shared.json")
    func unfiled() throws {
        let loose = Transaction(amount: 3, date: created, timeZoneID: kolkata, accountID: nil)
        let orphanSplit = TransactionSplit(transactionID: UUID(), amount: 1)
        let orphanFile = Attachment(transactionID: nil, fileName: "a.pdf", data: Data("pdf".utf8))
        let original = contents(
            LedgerSnapshot(transactions: [loose], splits: [orphanSplit], attachments: [orphanFile])
        )
        let files = try codec.encode(original)
        #expect(Set(files.paths) == ["manifest.json", "shared.json", "attachments/\(orphanFile.id.uuidString)"])
        #expect(try codec.decode(files) == original)
    }

    @Test("manifest.json is plain JSON with the format, its version and a checksum for every other file")
    func manifest() throws {
        let files = try codec.encode(contents())
        let data = try #require(files["manifest.json"])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["format", "formatVersion", "backup", "fingerprint", "files"])
        #expect(object["format"] as? String == "little-orbit-backup")
        #expect(object["formatVersion"] as? Int == 1)
        let listed = try #require(object["files"] as? [String: [String: Any]])
        #expect(Set(listed.keys) == Set(files.paths).subtracting(["manifest.json"]))
        for (path, entry) in listed {
            let bytes = try #require(files[path])
            #expect(entry["sha256"] as? String == FakeBackupHashing().sha256Hex(bytes))
            #expect(entry["byteSize"] as? Int == bytes.count)
        }
    }

    @Test("Reserved sections are written empty and listed as not yet populated")
    func reservedSections() throws {
        let decoded = try codec.decode(codec.encode(contents()))
        #expect(decoded.importRules.isEmpty)
        #expect(decoded.budgets.isEmpty)
        #expect(decoded.scheduledItems.isEmpty)
        #expect(decoded.reconciliationHistory.isEmpty)
        #expect(decoded.manifest.sections == BackupSection.populated)
        #expect(!BackupSection.populated.contains(.budgets))
    }

    @Test("The same data writes the same bytes, so an unchanged year can be cloned into the next backup")
    func stableBytes() throws {
        let first = try codec.encode(contents())
        var later = contents()
        later.manifest.createdAt = created + 86_400
        later.manifest.kind = .automatic
        let second = try codec.encode(later)
        for path in first.paths where path != "manifest.json" {
            #expect(first[path] == second[path])
        }
    }

    @Test("Every backup decodes on its own: the files of another backup aren't needed")
    func independent() throws {
        let first = try codec.encode(contents())
        var changed = ledger()
        changed.transactions.append(Transaction(amount: 9, date: created, timeZoneID: kolkata, accountID: cash.id))
        let second = try codec.encode(contents(changed))
        #expect(try codec.decode(second).transactions.count == 5)
        #expect(try codec.decode(first).transactions.count == 4)
    }

    @Test("A format-1 manifest with an encryption section is damaged, with no password step (S81, R5)")
    func oldEncryptedFile() throws {
        let files = try rewriteManifest(codec.encode(contents())) { object in
            object["encryption"] = ["algorithm": "AES-256-GCM", "iterations": 600_000]
        }
        #expect(throws: BackupError.damaged) { try codec.decode(files) }
    }

    @Test("An encryption section of any shape is damaged (S81)")
    func encryptionOfAnyShape() throws {
        for value: Any in ["yes", 1, [String: Any](), [Any]()] {
            let files = try rewriteManifest(codec.encode(contents())) { $0["encryption"] = value }
            #expect(throws: BackupError.damaged) { try codec.decode(files) }
        }
    }

    @Test("A newer format with an encryption section asks for an update, not damaged (R4)")
    func newerEncryptedFormat() throws {
        let files = try rewriteManifest(codec.encode(contents())) {
            $0["encryption"] = ["algorithm": "AES-256-GCM"]
            $0["formatVersion"] = BackupFormat.currentVersion + 1
        }
        #expect(throws: BackupError.newerFormat) { try codec.decode(files) }
    }

    @Test("A newer format asks for an update, before anything else is checked (S52)")
    func newerFormat() throws {
        var files = try rewriteManifest(codec.encode(contents())) {
            $0["formatVersion"] = BackupFormat.currentVersion + 1
            $0["files"] = "not-checked"
        }
        files["shared.json"] = nil
        #expect(throws: BackupError.newerFormat) { try codec.decode(files) }
    }

    @Test(
        "Anything that isn't a backup folder is damaged (S50)",
        arguments: [
            [:],
            ["Shopping list.txt": Data("milk, eggs".utf8)],
            ["little-orbit.littleorbit-backup": Data(#"{"format":"little-orbit-backup","formatVersion":1}"#.utf8)],
            ["manifest.json": Data()],
            ["manifest.json": Data(#"{"format":"something-else","formatVersion":1}"#.utf8)],
            ["manifest.json": Data([0xFF, 0xD8, 0xFF, 0xE0])],
        ] as [[String: Data]],
    )
    func notABackup(files: [String: Data]) {
        #expect(throws: BackupError.damaged) { try codec.decode(BackupSnapshotFiles(files)) }
    }

    @Test("A truncated manifest is damaged")
    func truncated() throws {
        var files = try codec.encode(contents())
        let manifest = try #require(files["manifest.json"])
        files["manifest.json"] = manifest.prefix(manifest.count / 2)
        #expect(throws: BackupError.damaged) { try codec.decode(files) }
    }

    @Test("A missing file is damaged")
    func missingFile() throws {
        for path in try codec.encode(contents()).paths where path != "manifest.json" {
            var files = try codec.encode(contents())
            files[path] = nil
            #expect(throws: BackupError.damaged) { try codec.decode(files) }
        }
    }

    @Test("A changed file fails its checksum and is damaged")
    func tampered() throws {
        for path in try codec.encode(contents()).paths where path != "manifest.json" {
            var files = try codec.encode(contents())
            files[path] = Data("{}".utf8)
            #expect(throws: BackupError.damaged) { try codec.decode(files) }
        }
    }

    @Test("Files the manifest doesn't list, such as .DS_Store, are ignored")
    func unlistedFiles() throws {
        var files = try codec.encode(contents())
        files[".DS_Store"] = Data([0, 1, 2])
        files["accounts/.DS_Store"] = Data([0, 1, 2])
        #expect(try codec.decode(files) == contents())
    }

    @Test("A manifest that lists a path outside the folder is damaged")
    func pathOutsideFolder() throws {
        let files = try rewriteManifest(codec.encode(contents())) { object in
            var listed = object["files"] as? [String: Any] ?? [:]
            listed["../shared.json"] = listed["shared.json"]
            object["files"] = listed
        }
        #expect(throws: BackupError.damaged) { try codec.decode(files) }
    }

    @Test("The fingerprint ignores record order and backup metadata (D116.3)")
    func fingerprint() throws {
        let ledger = contents().ledger
        var reversed = ledger
        reversed.accounts.reverse()
        #expect(try codec.fingerprint(of: ledger) == codec.fingerprint(of: reversed))
        var changed = ledger
        changed.accounts[0].name = "Renamed"
        #expect(try codec.fingerprint(of: ledger) != codec.fingerprint(of: changed))
    }

    @Test("The fingerprint follows each attachment's bytes, through their checksum (B1)")
    func fingerprintAttachments() throws {
        let ledger = contents().ledger
        var changedBytes = ledger
        changedBytes.attachments[0].data[0] ^= 0xFF
        #expect(try codec.fingerprint(of: ledger) != codec.fingerprint(of: changedBytes))
        var renamed = ledger
        renamed.attachments[0].fileName = "Other.jpg"
        #expect(try codec.fingerprint(of: ledger) != codec.fingerprint(of: renamed))
        #expect(try codec.fingerprint(of: ledger) == codec.fingerprint(of: contents().ledger))
    }

    private func rewriteManifest(
        _ files: BackupSnapshotFiles,
        _ change: (inout [String: Any]) -> Void,
    ) throws -> BackupSnapshotFiles {
        var files = files
        let data = try #require(files["manifest.json"])
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        files["manifest.json"] = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return files
    }

    @Test("A folder is checked file by file, streamed, with the same verdicts as decode (Tech Architect B1.2)")
    func streamedVerify() throws {
        let files = try codec.encode(contents())
        let folder = CountingFolder(files)
        let summary = try codec.verify(folder)
        #expect(summary.manifest.attachmentCount == 1)
        // Only the manifest is handed out whole; every listed file is streamed.
        #expect(folder.wholePaths == ["manifest.json"])
        #expect(Set(folder.streamedPaths) == Set(files.paths).subtracting(["manifest.json"]))

        var changed = files
        let receipt = try #require(files.paths.first { $0.hasPrefix("attachments/") })
        changed[receipt]?[0] ^= 0xFF
        #expect(throws: BackupError.damaged) { try codec.verify(changed) }
        var missing = files
        missing[receipt] = nil
        #expect(throws: BackupError.damaged) { try codec.verify(missing) }
        var unlisted = files
        unlisted["extra.json"] = Data("{}".utf8)
        #expect(try codec.verify(unlisted).manifest == summary.manifest)
    }

    @Test("Restoring a stored folder reads only the files the manifest lists, the manifest first (B1.2)")
    func decodeReadingListedFiles() throws {
        var files = try codec.encode(contents())
        files["extra.bin"] = Data(count: 1_000)
        let folder = CountingFolder(files)
        #expect(try codec.decode(reading: folder) == contents())
        #expect(folder.wholePaths.first == "manifest.json")
        #expect(!folder.wholePaths.contains("extra.bin"))
        #expect(folder.streamedPaths.isEmpty)
    }

    @Test("The incremental digest matches hashing in one go, whatever the chunks")
    func chunkedDigest() {
        let data = Data((0..<1_000).map { UInt8($0 % 251) })
        let digest = FakeBackupHashing().makeDigest()
        var start = 0
        while start < data.count {
            let end = min(start + 37, data.count)
            data[start..<end].withUnsafeBytes { digest.update($0) }
            start = end
        }
        #expect(digest.finish() == FakeBackupHashing().sha256Hex(data))
    }
}

/// A folder in memory that records which files were read whole and which were streamed.
final class CountingFolder: BackupFileReading {
    private let files: BackupSnapshotFiles
    private(set) var wholePaths: [String] = []
    private(set) var streamedPaths: [String] = []

    init(_ files: BackupSnapshotFiles) {
        self.files = files
    }

    func data(at path: String) throws -> Data? {
        wholePaths.append(path)
        return files[path]
    }

    func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        streamedPaths.append(path)
        return try files.stream(path, through: body)
    }
}
