import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

#if canImport(AppleArchive)
    /// A backup folder's files, recording every chunk handed out and any file read whole.
    private final class ChunkFolder: BackupFileReading, @unchecked Sendable {
        private let files: BackupSnapshotFiles
        private let lock = NSLock()
        private var chunks: [Int] = []
        private var whole: [String] = []

        init(_ files: BackupSnapshotFiles) {
            self.files = files
        }

        var largestChunk: Int { lock.withLock { chunks.max() ?? 0 } }
        var readWhole: [String] { lock.withLock { whole } }

        func data(at path: String) throws -> Data? {
            lock.withLock { whole.append(path) }
            return files[path]
        }

        func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
            guard let data = files[path] else {
                return false
            }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let end = min(offset + BackupChunk.size, buffer.count)
                    lock.withLock { chunks.append(end - offset) }
                    try body(UnsafeRawBufferPointer(rebasing: buffer[offset..<end]))
                    offset = end
                }
            }
            return true
        }
    }

    /// B2: an export streams each file into an Apple Archive file, one `writeBlob` per chunk, never holding a file.
    @Suite("Apple Archive export file", .timeLimit(.minutes(2)))
    struct AppleArchiveExportFileTests {
        private let archiving = AppleArchiveBackupArchiving()
        private let files = BackupSnapshotFiles([
            "manifest.json": Data("{\"m\":1}".utf8),
            "shared.json": Data("shared".utf8),
            "accounts/A/2026.json": Data("year".utf8),
            "attachments/B": Data((0..<(BackupChunk.size * 5 / 2)).map { UInt8(truncatingIfNeeded: $0 &* 7) }),
            "attachments/empty": Data(),
        ])

        private func list(_ files: BackupSnapshotFiles) -> [BackupArchiveFile] {
            let others = files.paths.filter { $0 != "manifest.json" }.sorted()
            return (["manifest.json"] + others)
                .map {
                    BackupArchiveFile(path: $0, byteSize: Int64(files[$0]?.count ?? 0))
                }
        }

        private func url() -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).aar")
        }

        @Test("The file holds the same files and folders, manifest first, streamed in chunks of at most 1 MB")
        func streams() throws {
            let folder = ChunkFolder(files)
            let url = url()
            defer { try? FileManager.default.removeItem(at: url) }
            try archiving.archive(list(files), from: folder, to: url)

            #expect(folder.readWhole.isEmpty)
            #expect(folder.largestChunk <= BackupChunk.size)
            let entries = try archiving.entries(of: .file(url)) { _ in .data }
            #expect(try BackupArchiveSafety.files(from: entries) == files)
            #expect(entries.first?.path == "manifest.json")
            let folders = entries.filter { $0.kind == .directory }.map(\.path)
            #expect(Set(folders) == ["accounts", "accounts/A", "attachments"])
        }

        @Test("A file that isn't its listed size is damaged; an existing file is never overwritten")
        func refuses() throws {
            let url = url()
            defer { try? FileManager.default.removeItem(at: url) }
            var wrong = list(files)
            wrong[wrong.count - 1].byteSize += 1
            #expect(throws: BackupError.damaged) { try archiving.archive(wrong, from: ChunkFolder(files), to: url) }
            try? FileManager.default.removeItem(at: url)
            var short = list(files)
            short[1].byteSize -= 1
            #expect(throws: BackupError.damaged) { try archiving.archive(short, from: ChunkFolder(files), to: url) }
            try? FileManager.default.removeItem(at: url)

            try Data("keep".utf8).write(to: url)
            #expect(throws: (any Error).self) { try archiving.archive(list(files), from: ChunkFolder(files), to: url) }
            #expect(try Data(contentsOf: url) == Data("keep".utf8))
        }
    }
#endif
