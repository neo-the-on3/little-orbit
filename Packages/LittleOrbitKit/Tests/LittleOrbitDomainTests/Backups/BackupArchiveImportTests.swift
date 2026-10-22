import Foundation
import LittleOrbitDomain
import Testing

/// An archive as a list of entries in memory. It records, per pass, which files' bytes were handed out whole and
/// which were streamed, and counts the bytes handed out whole, so a test can show that only the manifest is read
/// before the version check (D197a.1) and that checking never hands out an attachment (B1.3).
final class SpyArchiving: BackupArchiving, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Data: [BackupArchiveEntry]] = [:]
    private(set) var readPaths: [[String]] = []
    private(set) var streamedPaths: [[String]] = []
    /// Every byte handed out in an entry, across all passes.
    private(set) var bytesHandedOut = 0

    /// An archive holding exactly `entries`, unsafe ones included.
    func crafted(_ entries: [BackupArchiveEntry]) -> Data {
        lock.withLock {
            let data = Data(UUID().uuidString.utf8)
            stored[data] = entries
            return data
        }
    }

    func archive(_ files: BackupSnapshotFiles) throws -> Data {
        crafted(files.paths.map { BackupArchiveEntry(path: $0, kind: .file(files[$0])) })
    }

    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry] {
        try lock.withLock {
            guard case .data(let key) = archive, let entries = stored[key] else {
                throw BackupError.damaged
            }
            var read: [String] = []
            var streamed: [String] = []
            let result = entries.map { entry in
                guard case .file(let data) = entry.kind else {
                    return entry
                }
                switch reading(entry.path) {
                case .skip:
                    return BackupArchiveEntry(path: entry.path, kind: .file(nil))
                case .data:
                    read.append(entry.path)
                    bytesHandedOut += data?.count ?? 0
                    return BackupArchiveEntry(path: entry.path, kind: .file(data))
                case .stream(let body):
                    streamed.append(entry.path)
                    // In small chunks, the way a real file is read.
                    let bytes = data ?? Data()
                    var start = bytes.startIndex
                    while start < bytes.endIndex {
                        let end = min(start + 7, bytes.endIndex)
                        bytes[start..<end].withUnsafeBytes { body($0) }
                        start = end
                    }
                    return BackupArchiveEntry(path: entry.path, kind: .file(nil))
                }
            }
            readPaths.append(read)
            streamedPaths.append(streamed)
            return result
        }
    }
}

/// D195a.2, D197.1 and D197a.1: an imported archive is checked manifest entry → version → unsafe entries →
/// checksums, in memory, stopping at the first failure (L21, L22, L34, L37, L40–L42).
@Suite("Backup archive import")
struct BackupArchiveImportTests {
    private let codec = BackupCodec(hashing: FakeBackupHashing())
    private let archiving = SpyArchiving()

    private var importer: BackupArchiveImport {
        BackupArchiveImport(archiving: archiving, codec: codec)
    }

    private func snapshot() throws -> BackupSnapshotFiles {
        let ledger = LedgerSnapshot(accounts: [
            Account(name: "Everyday Savings", type: .savings, currencyCode: "EUR", openingBalance: 100, sortOrder: 1)
        ])
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: Date(timeIntervalSince1970: 1_792_640_525),
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: 1,
            transactionCount: 0,
            attachmentCount: 0,
            month: "2026-10",
        )
        return try codec.encode(BackupContents(manifest: manifest, ledger: ledger))
    }

    private func entries(_ files: BackupSnapshotFiles) -> [BackupArchiveEntry] {
        files.paths.map { BackupArchiveEntry(path: $0, kind: .file(files[$0])) }
    }

    private func newerManifest(_ files: BackupSnapshotFiles) throws -> Data {
        let data = try #require(files["manifest.json"])
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = BackupFormat.currentVersion + 1
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// The steps `archive` went through before it passed or failed.
    private func steps(_ archive: Data) -> (steps: [BackupImportStep], error: BackupError?) {
        var steps: [BackupImportStep] = []
        do {
            _ = try importer.contents(of: archive) { steps.append($0) }
            return (steps, nil)
        } catch {
            return (steps, error as? BackupError)
        }
    }

    @Test("A valid archive passes all four steps, in order, and reads only the manifest before the version (L42)")
    func validOrder() throws {
        let files = try snapshot()
        let archive = archiving.crafted(entries(files))
        let result = steps(archive)
        #expect(result.steps == [.manifestEntry, .formatVersion, .unsafeEntries, .checksums])
        #expect(result.error == nil)
        #expect(archiving.readPaths.first == ["manifest.json"])
        #expect(try importer.contents(of: archive).accounts.map(\.name) == ["Everyday Savings"])
    }

    @Test("Each failing step stops the import there (L42)")
    func stopsAtFirstFailure() throws {
        let files = try snapshot()
        var withoutManifest = files
        withoutManifest["manifest.json"] = nil
        var newer = entries(files)
        newer.removeAll { $0.path == "manifest.json" }
        newer.append(BackupArchiveEntry(path: "manifest.json", kind: .file(try newerManifest(files))))
        let unsafe = entries(files) + [BackupArchiveEntry(path: "../outside.json", kind: .file(Data("x".utf8)))]
        var changed = files
        changed["shared.json"]?.append(0x20)
        struct Case {
            var archive: [BackupArchiveEntry]
            var steps: [BackupImportStep]
            var error: BackupError
        }
        let cases = [
            Case(archive: entries(withoutManifest), steps: [.manifestEntry], error: .damaged),
            Case(archive: newer, steps: [.manifestEntry, .formatVersion], error: .newerFormat),
            Case(archive: unsafe, steps: [.manifestEntry, .formatVersion, .unsafeEntries], error: .damaged),
            Case(archive: entries(changed), steps: BackupImportStep.allCases, error: .damaged),
        ]
        for item in cases {
            let result = steps(archiving.crafted(item.archive))
            #expect(result.steps == item.steps)
            #expect(result.error == item.error)
        }
    }

    @Test("A newer format wins over unlisted files, a bad checksum and a ../ entry (L34, L40)")
    func newerWins() throws {
        let files = try snapshot()
        var archive = entries(files).filter { $0.path != "manifest.json" && $0.path != "shared.json" }
        archive += [
            BackupArchiveEntry(path: "manifest.json", kind: .file(try newerManifest(files))),
            BackupArchiveEntry(path: "shared.json", kind: .file(Data("changed".utf8))),
            BackupArchiveEntry(path: "unlisted.json", kind: .file(Data("{}".utf8))),
            BackupArchiveEntry(path: "../outside.json", kind: .file(Data("x".utf8))),
        ]
        #expect(throws: BackupError.newerFormat) { try importer.contents(of: archiving.crafted(archive)) }
        // Only the manifest's bytes were read.
        #expect(archiving.readPaths == [["manifest.json"]])
    }

    @Test(
        "An absent or unsafe manifest entry is damaged, even when its text declares a newer format (L41 a–f)",
        arguments: ["a", "b", "c", "d1", "d2", "e", "f"],
    )
    func manifestEntry(kind: String) throws {
        let files = try snapshot()
        let newer = try newerManifest(files)
        let rest = entries(files).filter { $0.path != "manifest.json" }
        let manifest: [BackupArchiveEntry] =
            switch kind {
            case "a": [BackupArchiveEntry(path: "sub/manifest.json", kind: .file(newer))]
            case "b": [BackupArchiveEntry(path: "manifest.json", kind: .symbolicLink(target: "shared.json"))]
            case "c": [BackupArchiveEntry(path: "manifest.json", kind: .hardLink(target: "shared.json"))]
            case "d1": [BackupArchiveEntry(path: "../manifest.json", kind: .file(newer))]
            case "d2": [BackupArchiveEntry(path: "/manifest.json", kind: .file(newer))]
            case "e":
                [
                    BackupArchiveEntry(path: "manifest.json", kind: .file(newer)),
                    BackupArchiveEntry(path: "./manifest.json", kind: .file(newer)),
                ]
            default: [BackupArchiveEntry(path: "manifest.json", kind: .file(Data("{\"formatVersion\": 2".utf8)))]
            }
        let result = steps(archiving.crafted(rest + manifest))
        #expect(result.error == .damaged)
        #expect(result.steps == [.manifestEntry] || kind == "f" && result.steps == [.manifestEntry, .formatVersion])
    }

    @Test(
        "Absolute paths, .. and links pointing outside are damaged (L21 a–d)",
        arguments: [
            BackupArchiveEntry(path: "/tmp/x.json", kind: .file(Data("x".utf8))),
            BackupArchiveEntry(path: "../outside.json", kind: .file(Data("x".utf8))),
            BackupArchiveEntry(path: "attachments/link", kind: .symbolicLink(target: "../../outside")),
            BackupArchiveEntry(path: "attachments/hard", kind: .hardLink(target: "../outside.json")),
        ],
    )
    func unsafeEntry(entry: BackupArchiveEntry) throws {
        let archive = archiving.crafted(entries(try snapshot()) + [entry])
        let result = steps(archive)
        #expect(result.error == .damaged)
        #expect(result.steps.last == .unsafeEntries)
    }

    @Test("A changed or missing file, or a missing or unreadable manifest, is damaged (L22, L37)")
    func damagedFiles() throws {
        let files = try snapshot()
        var changed = files
        changed["shared.json"]?.append(0x20)
        var missing = files
        missing["shared.json"] = nil
        var noManifest = files
        noManifest["manifest.json"] = nil
        var notJSON = files
        notJSON["manifest.json"] = Data("not json".utf8)
        var noVersion = files
        noVersion["manifest.json"] = Data(#"{"format":"little-orbit-backup","formatVersion":"one"}"#.utf8)
        for variant in [changed, missing, noManifest, notJSON, noVersion] {
            #expect(throws: BackupError.damaged) { try importer.contents(of: archiving.crafted(entries(variant))) }
        }
        #expect(throws: BackupError.damaged) { try importer.contents(of: Data("Shopping list".utf8)) }
    }

    /// A backup with two 4 KB attachments, and their bytes.
    private func snapshotWithAttachments() throws -> (files: BackupSnapshotFiles, attachmentBytes: Int) {
        let account = Account(name: "Wallet", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 1)
        let spend = Transaction(amount: 10, accountID: account.id)
        let attachments = (0..<2)
            .map { index in
                Attachment(
                    transactionID: spend.id,
                    fileName: "Receipt \(index).jpg",
                    contentType: "image/jpeg",
                    byteSize: 4_096,
                    data: Data(repeating: UInt8(index + 1), count: 4_096),
                )
            }
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: Date(timeIntervalSince1970: 1_792_640_525),
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: 1,
            transactionCount: 1,
            attachmentCount: 2,
            month: "2026-10",
        )
        let ledger = LedgerSnapshot(accounts: [account], transactions: [spend], attachments: attachments)
        return (try codec.encode(BackupContents(manifest: manifest, ledger: ledger)), 2 * 4_096)
    }

    @Test("Checking hands out no attachment: only the manifest, the rest streamed (Tech Architect B1.3)")
    func checkHoldsNoAttachment() throws {
        let (files, _) = try snapshotWithAttachments()
        let archive = archiving.crafted(entries(files))
        let summary = try importer.check(.data(archive))
        #expect(summary.manifest.attachmentCount == 2)
        let manifestBytes = try #require(files["manifest.json"]).count
        #expect(archiving.bytesHandedOut == manifestBytes)
        #expect(archiving.readPaths == [["manifest.json"], []])
        #expect(Set(archiving.streamedPaths.last ?? []) == Set(files.paths).subtracting(["manifest.json"]))
    }

    @Test("Import reads each attachment once, after all four steps pass; never a second copy (B1.3)")
    func importReadsAttachmentsOnce() throws {
        let (files, attachmentBytes) = try snapshotWithAttachments()
        let archive = archiving.crafted(entries(files))
        var stepsDone: [BackupImportStep] = []
        var handedOutWhenChecked: Int?
        let contents = try importer.contents(of: .data(archive)) { step in
            stepsDone.append(step)
            if step == .checksums {
                handedOutWhenChecked = archiving.bytesHandedOut
            }
        }
        #expect(contents.attachments.map(\.data.count) == [4_096, 4_096])
        let manifestBytes = try #require(files["manifest.json"]).count
        let everything = files.paths.compactMap { files[$0]?.count }.reduce(0, +)
        // Before the checksums, only the manifest; in all, the manifest twice and every other file once.
        #expect(handedOutWhenChecked == manifestBytes)
        #expect(archiving.bytesHandedOut == everything + manifestBytes)
        #expect(everything > attachmentBytes)
        #expect(archiving.readPaths.count == 3)
    }

    @Test("A file changed between the check and the read is damaged, as a different entry list is (B1.1)")
    func changedBetweenPasses() throws {
        let (files, _) = try snapshotWithAttachments()
        var corrupted = files
        let attachment = try #require(files.paths.first { $0.hasPrefix("attachments/") })
        corrupted[attachment]?[0] ^= 0xFF
        #expect(throws: BackupError.damaged) { try importer.check(.data(archiving.crafted(entries(corrupted)))) }
    }
}
