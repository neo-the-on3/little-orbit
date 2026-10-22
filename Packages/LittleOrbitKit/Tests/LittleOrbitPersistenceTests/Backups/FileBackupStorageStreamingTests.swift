import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// Attachment bytes by ID that record each chunk they hand out.
private final class ChunkedBytes: BackupAttachmentReading, @unchecked Sendable {
    private let bytes: BackupLedgerAttachments
    private let lock = NSLock()
    private var chunks: [UUID: [Int]] = [:]

    init(_ ledger: LedgerSnapshot) {
        bytes = BackupLedgerAttachments(ledger)
    }

    func chunks(of id: UUID) -> [Int] {
        lock.withLock { chunks[id] ?? [] }
    }

    func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        try bytes.stream(id) { chunk in
            lock.withLock { chunks[id, default: []].append(chunk.count) }
            try body(chunk)
        }
    }

    func mappedData(for id: UUID) throws -> Data? {
        Issue.record("A backup folder is never written from an attachment held whole")
        return try bytes.mappedData(for: id)
    }
}

/// Tech Architect B1: the folder store writes attachment files from their bytes in chunks, clones the unchanged
/// ones, and reads them back in chunks; a picked file's attachments go to a scratch folder in the staging folder.
@Suite("File backup storage streams attachments", .timeLimit(.minutes(2)))
struct FileBackupStorageStreamingTests {
    private static let size = BackupChunk.size * 5 / 2

    func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "backups-\(UUID().uuidString)",
            isDirectory: true,
        )
    }

    func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }

    private func ledger() -> LedgerSnapshot {
        let attachments = (0..<2)
            .map { index in
                var data = Data(count: Self.size)
                data.withUnsafeMutableBytes { raw in
                    for offset in stride(from: 0, to: raw.count, by: 4_093) {
                        raw[offset] = UInt8(truncatingIfNeeded: offset &+ index)
                    }
                }
                return Attachment(
                    transactionID: UUID(),
                    fileName: "Scan \(index).pdf",
                    contentType: "application/pdf",
                    byteSize: Int64(data.count),
                    data: data,
                )
            }
        return LedgerSnapshot(attachments: attachments)
    }

    private func path(_ id: UUID) -> String {
        "attachments/\(id.uuidString)"
    }

    private let json = BackupSnapshotFiles(["manifest.json": Data("{\"m\":1}".utf8), "shared.json": Data("s".utf8)])

    @Test("Attachment files are written in chunks; an unchanged one is cloned, never read from its bytes")
    func writesInChunks() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let ledger = ledger()
        let ids = Dictionary(uniqueKeysWithValues: ledger.attachments.map { (path($0.id), $0.id) })
        let first = UUID()
        let firstBytes = ChunkedBytes(ledger)
        try storage.write(
            json,
            attachments: BackupAttachmentWrites(ids: ids, bytes: firstBytes),
            id: first,
            cloningFrom: nil,
        )
        for attachment in ledger.attachments {
            let chunks = firstBytes.chunks(of: attachment.id)
            #expect(chunks.count == 3)
            #expect(chunks.allSatisfy { $0 <= BackupChunk.size })
        }

        let second = UUID()
        let secondBytes = ChunkedBytes(ledger)
        let kept = ledger.attachments[0]
        let writes = BackupAttachmentWrites(ids: ids, unchanged: [path(kept.id)], bytes: secondBytes)
        try storage.write(json, attachments: writes, id: second, cloningFrom: first)
        #expect(secondBytes.chunks(of: kept.id).isEmpty)
        #expect(secondBytes.chunks(of: ledger.attachments[1].id).count == 3)

        let files = try storage.files(id: second)
        for attachment in ledger.attachments {
            var read: [Int] = []
            var bytes = Data()
            #expect(
                try files.stream(path(attachment.id)) {
                    read.append($0.count)
                    bytes.append(contentsOf: $0)
                }
            )
            #expect(bytes == attachment.data)
            #expect(read.allSatisfy { $0 <= BackupChunk.size })
        }
        #expect(try files.data(at: "manifest.json") == json["manifest.json"])
        // The clone is its own file: changing the earlier one leaves it alone.
        try Data("changed".utf8).write(to: storage.folderURL(first).appendingPathComponent(path(kept.id)))
        #expect(try storage.files(id: second).data(at: path(kept.id)) == kept.data)
    }

    @Test("A path marked unchanged with no earlier file is written from its bytes")
    func unchangedWithoutEarlier() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let ledger = ledger()
        let attachment = ledger.attachments[0]
        let bytes = ChunkedBytes(ledger)
        let writes = BackupAttachmentWrites(
            ids: [path(attachment.id): attachment.id],
            unchanged: [path(attachment.id)],
            bytes: bytes,
        )
        let id = UUID()
        try storage.write(json, attachments: writes, id: id, cloningFrom: UUID())
        #expect(try storage.files(id: id).data(at: path(attachment.id)) == attachment.data)
    }

    @Test("A scratch folder is in the staging folder, holds what's written to it, and goes when removed or relaunched")
    func scratch() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let scratch = try storage.makeScratch()
        let file = try scratch.create("attachments/A")
        let bytes = Data((0..<10).map { UInt8($0) })
        try bytes.withUnsafeBytes { try file.write(UnsafeRawBufferPointer(rebasing: $0[0..<4])) }
        try bytes.withUnsafeBytes { try file.write(UnsafeRawBufferPointer(rebasing: $0[4..<10])) }
        try file.close()
        #expect(try scratch.data(at: "attachments/A") == bytes)
        #expect(try scratch.data(at: "../outside") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.stagingURL.path).count == 1)
        #expect(try storage.storedIDs().isEmpty)

        scratch.remove()
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.stagingURL.path).isEmpty)

        _ = try storage.makeScratch().create("attachments/B")
        let relaunched = try FileBackupStorage(folder: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: relaunched.stagingURL.path).isEmpty)
    }
}

extension FileBackupStorageStreamingTests {
    @Test("An export's folder is in the staging folder, removed with its file, and swept at the next launch (B2)")
    func exportFolder() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let export = try storage.makeExportFolder()
        #expect(export.lastPathComponent.hasSuffix(".export"))
        #expect(
            export.deletingLastPathComponent().standardizedFileURL.path == storage.stagingURL.standardizedFileURL.path
        )
        let file = export.appendingPathComponent("little-orbit 2026-10-22 0912.littleorbit-backup")
        try Data("archive".utf8).write(to: file)
        #expect(try storage.storedIDs().isEmpty)

        // Only an export folder of this store is ever removed.
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).export")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        storage.removeExport(outside.appendingPathComponent("x"))
        #expect(FileManager.default.fileExists(atPath: outside.path))
        storage.removeExport(storage.folderURL(UUID()).appendingPathComponent("manifest.json"))

        storage.removeExport(file)
        #expect(!FileManager.default.fileExists(atPath: export.path))

        let left = try storage.makeExportFolder()
        try Data("archive".utf8).write(to: left.appendingPathComponent("a.littleorbit-backup"))
        let relaunched = try FileBackupStorage(folder: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: relaunched.stagingURL.path).isEmpty)
    }
}
