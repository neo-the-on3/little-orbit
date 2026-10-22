import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

#if canImport(AppleArchive)
    import AppleArchive
    import System
#endif

#if canImport(AppleArchive)
    /// D195a.1, L18, L19: the exported file is the folder in one uncompressed Apple Archive, read in memory.
    @Suite("Apple Archive backup file")
    struct AppleArchiveBackupArchivingTests {
        private let archiving = AppleArchiveBackupArchiving()
        private let files = BackupSnapshotFiles([
            "manifest.json": Data("{\"m\":1}".utf8),
            "shared.json": Data("shared".utf8),
            "accounts/A/2026.json": Data("year".utf8),
            "attachments/B": Data(repeating: 0xAB, count: 70_000),
            "attachments/empty": Data(),
        ])

        @Test("An archive lists the same files and folders back")
        func roundTrip() throws {
            let data = try archiving.archive(files)
            let read = try BackupArchiveSafety.files(from: archiving.entries(of: data))
            #expect(read == files)
            let folders = try archiving.entries(of: data).filter { $0.kind == .directory }.map(\.path)
            #expect(Set(folders) == ["accounts", "accounts/A", "attachments"])
        }

        @Test("It's uncompressed: an attachment's bytes appear as they are")
        func uncompressed() throws {
            let data = try archiving.archive(files)
            #expect(data.range(of: Data(repeating: 0xAB, count: 70_000)) != nil)
        }

        @Test("A folder archived with its symlink and hard link is refused before anything is extracted (L3)")
        func linksFromTheSystemArchiver() throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let folder = root.appendingPathComponent("backup")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("shared".utf8).write(to: folder.appendingPathComponent("shared.json"))
            try FileManager.default.createSymbolicLink(
                atPath: folder.appendingPathComponent("outside").path,
                withDestinationPath: "/etc/hosts",
            )
            try FileManager.default.linkItem(
                at: folder.appendingPathComponent("shared.json"),
                to: folder.appendingPathComponent("hard.json"),
            )
            let archive = root.appendingPathComponent("backup.littleorbit-backup")
            let file = try #require(
                ArchiveByteStream.fileStream(
                    path: FilePath(archive.path),
                    mode: .writeOnly,
                    options: [.create, .truncate],
                    permissions: FilePermissions(rawValue: 0o600),
                )
            )
            let encoder = try #require(ArchiveStream.encodeStream(writingTo: file))
            let keys = try #require(ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DAT,MOD,HLC"))
            try encoder.writeDirectoryContents(archiveFrom: FilePath(folder.path), keySet: keys)
            try encoder.close()
            try file.close()

            let entries = try archiving.entries(of: Data(contentsOf: archive))
            #expect(entries.contains { $0.kind == .symbolicLink(target: "/etc/hosts") })
            #expect(entries.contains { if case .hardLink = $0.kind { true } else { false } })
            #expect(throws: BackupError.damaged) { try BackupArchiveSafety.files(from: entries) }
        }

        @Test("Only the bytes asked for are read; the other files are skipped (D197a.1)")
        func readsOnlyWhatIsAsked() throws {
            let data = try archiving.archive(files)
            let entries = try archiving.entries(of: data) { $0 == "manifest.json" }
            #expect(entries.contains(BackupArchiveEntry(path: "manifest.json", kind: .file(Data("{\"m\":1}".utf8)))))
            #expect(entries.contains(BackupArchiveEntry(path: "attachments/B", kind: .file(nil))))
            #expect(entries.filter { $0.kind == .file(nil) }.count == files.paths.count - 1)
        }

        @Test("A newer manifest next to ../outside.json asks for an update and writes nothing (L40)")
        func newerWithDotDot() throws {
            let codec = BackupCodec(hashing: CryptoKitBackupHashing())
            let crafted = BackupSnapshotFiles([
                "manifest.json": Data(#"{"format":"little-orbit-backup","formatVersion":2}"#.utf8),
                "../outside.json": Data("{}".utf8),
            ])
            let data = try archiving.archive(crafted)
            let outside = FileManager.default.temporaryDirectory.deletingLastPathComponent()
                .appendingPathComponent("outside.json")
            #expect(throws: BackupError.newerFormat) {
                try BackupArchiveImport(archiving: archiving, codec: codec).contents(of: data)
            }
            #expect(!FileManager.default.fileExists(atPath: outside.path))
        }

        @Test("The manifest is the first entry, and an entry the reader refuses stands for the rest (L34, L40)")
        func manifestFirst() throws {
            let data = try archiving.archive(files)
            #expect(try archiving.entries(of: data).first?.path == "manifest.json")
            let unsafe = try archiving.archive(
                BackupSnapshotFiles(["manifest.json": Data("{}".utf8), "/abs.json": Data(), "z.json": Data()])
            )
            let entries = try archiving.entries(of: unsafe)
            #expect(entries.first == BackupArchiveEntry(path: "manifest.json", kind: .file(Data("{}".utf8))))
            #expect(entries.last == BackupArchiveEntry(path: "", kind: .other))
            #expect(throws: BackupError.damaged) { try BackupArchiveSafety.check(entries) }
        }

        @Test("A file is read where it is, its blobs streamed in fixed-size chunks, never held whole (B1.1)")
        func streamsFromFile() throws {
            let large = Data((0..<(AppleArchiveBackupArchiving.chunkSize * 3 + 5)).map { UInt8($0 % 251) })
            var withLarge = files
            withLarge["attachments/large"] = large
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("stream-\(UUID().uuidString).littleorbit-backup")
            try archiving.archive(withLarge).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            var chunks: [Int] = []
            var streamed = Data()
            let entries = try archiving.entries(of: .file(url)) { path in
                guard path == "attachments/large" else {
                    return path == "manifest.json" ? .data : .skip
                }
                return .stream {
                    chunks.append($0.count)
                    streamed.append(contentsOf: $0)
                }
            }
            #expect(streamed == large)
            #expect(chunks.count == 4)
            #expect(chunks.allSatisfy { $0 <= AppleArchiveBackupArchiving.chunkSize })
            #expect(entries.contains(BackupArchiveEntry(path: "attachments/large", kind: .file(nil))))
            #expect(entries.first == BackupArchiveEntry(path: "manifest.json", kind: .file(files["manifest.json"])))
            #expect(try BackupArchiveSafety.files(from: archiving.entries(of: .file(url)) { _ in .data }) == withLarge)
        }

        @Test("A file that can't be opened throws its read error, not 'damaged' (N1)")
        func unreadableFile() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
            #expect(throws: CocoaError.self) { try archiving.entries(of: .file(url)) { _ in .skip } }
        }

        @Test("A file that isn't an archive is damaged")
        func notAnArchiveFile() throws {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("text-\(UUID().uuidString)")
            try Data("Shopping list".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: BackupError.damaged) { try archiving.entries(of: .file(url)) { _ in .skip } }
        }

        @Test("Something that isn't an archive is damaged", arguments: [Data(), Data("not an archive".utf8)])
        func notAnArchive(data: Data) {
            #expect(throws: BackupError.damaged) { try archiving.entries(of: data) }
        }
    }
#endif
