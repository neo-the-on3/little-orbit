import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// Tech Architect on 6455556 (B1): a symlink is never a backup and never followed. One in the Backups folder isn't
/// listed, and Delete never changes the mode of, writes to or walks into anything a link points at, at any depth:
/// a link inside a backup folder is removed as a link. A Backups folder that can be listed but not searched is a
/// read failure, never an empty list (D214.1).
@Suite("File backup storage: symlinks are never followed (B1)", .serialized, .timeLimit(.minutes(2)))
struct FileBackupStorageSymlinkTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("symlinks-\(UUID().uuidString)", isDirectory: true)
    private var folder: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    private var outside: URL { root.appendingPathComponent("Outside", isDirectory: true) }
    private let fileManager = FileManager.default

    private func cleanUp() {
        if let enumerator = fileManager.enumerator(atPath: root.path) {
            while let relative = enumerator.nextObject() as? String {
                let path = root.path + "/" + relative
                if (try? fileManager.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeDirectory {
                    try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                }
            }
        }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? fileManager.removeItem(at: root)
    }

    private func mode(_ url: URL) throws -> Int {
        try #require((fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue)
    }

    /// An outside folder at `mode`, with a file and an inner folder at `innerMode` that has a file too.
    private func outsideFolder(_ name: String, mode: Int, innerMode: Int) throws -> URL {
        let url = outside.appendingPathComponent(name, isDirectory: true)
        let inner = url.appendingPathComponent("inner", isDirectory: true)
        try fileManager.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: url.appendingPathComponent("keep.txt"))
        try Data("inner".utf8).write(to: inner.appendingPathComponent("keep.txt"))
        try fileManager.setAttributes([.posixPermissions: innerMode], ofItemAtPath: inner.path)
        try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url
    }

    /// The modes and contents of `url` and its inner folder, read without changing either.
    private func snapshot(_ url: URL) throws -> [String] {
        let inner = url.appendingPathComponent("inner", isDirectory: true)
        return [
            String(try mode(url), radix: 8),
            String(try mode(inner), radix: 8),
            try fileManager.contentsOfDirectory(atPath: url.path).sorted().joined(separator: ","),
            try fileManager.contentsOfDirectory(atPath: inner.path).sorted().joined(separator: ","),
            try String(bytes: Data(contentsOf: url.appendingPathComponent("keep.txt")), encoding: .utf8) ?? "",
            try String(bytes: Data(contentsOf: inner.appendingPathComponent("keep.txt")), encoding: .utf8) ?? "",
        ]
    }

    private func backup(_ storage: FileBackupStorage) throws -> UUID {
        let id = UUID()
        let manifest = Data("{\"id\":\"\(id.uuidString)\"}".utf8)
        try storage.write(BackupSnapshotFiles(["manifest.json": manifest]), id: id, cloningFrom: nil)
        return id
    }

    @Test("A symlink in the Backups folder, to a folder that looks like a backup, is never listed or touched")
    func linkInBackupsFolder() throws {
        defer { cleanUp() }
        let storage = try FileBackupStorage(folder: folder)
        let real = try backup(storage)
        // A copy of a real backup outside, manifest and all, linked in by a backup ID and by a date.
        let lookalike = try outsideFolder("lookalike", mode: 0o500, innerMode: 0o500)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lookalike.path)
        let linkedID = UUID()
        try Data("{\"id\":\"\(linkedID.uuidString)\"}".utf8)
            .write(to: lookalike.appendingPathComponent("manifest.json"))
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: lookalike.path)
        let before = try snapshot(lookalike)
        try fileManager.createSymbolicLink(
            at: folder.appendingPathComponent(linkedID.uuidString),
            withDestinationURL: lookalike,
        )
        try fileManager.createSymbolicLink(
            at: folder.appendingPathComponent("2026-10-23-11-00"),
            withDestinationURL: lookalike,
        )

        #expect(try storage.storedIDs() == [real])
        #expect(throws: BackupError.notFound) { try storage.listing(id: linkedID) }
        #expect(throws: BackupError.notFound) { try storage.read(id: linkedID) }
        #expect(throws: BackupError.notFound) { try storage.files(id: linkedID) }
        #expect(storage.folderCreationDate(id: linkedID) == nil)
        try storage.delete(id: linkedID)

        #expect(try snapshot(lookalike) == before)
        #expect(try storage.storedIDs() == [real])
    }

    @Test("Delete removes a link inside a backup folder as a link: what it points at keeps its modes and contents")
    func linkInsideBackup() throws {
        try deleteWithLinks(denyFolder: false)
    }

    @Test("The same when the backup folder can't be read, so Delete gives it access first (D214)")
    func linkInsideUnreadableBackup() throws {
        try deleteWithLinks(denyFolder: true)
    }

    private func deleteWithLinks(denyFolder: Bool) throws {
        defer { cleanUp() }
        let storage = try FileBackupStorage(folder: folder)
        let id = try backup(storage)
        let url = storage.folderURL(id)
        let readOnly = try outsideFolder("read-only", mode: 0o500, innerMode: 0o500)
        let open = try outsideFolder("open", mode: 0o755, innerMode: 0o555)
        let nested = url.appendingPathComponent("attachments/deep", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: url.appendingPathComponent("link"), withDestinationURL: readOnly)
        try fileManager.createSymbolicLink(at: nested.appendingPathComponent("link"), withDestinationURL: open)
        try fileManager.createSymbolicLink(
            at: nested.appendingPathComponent("file"),
            withDestinationURL:
                open.appendingPathComponent("keep.txt"),
        )
        let before = try [snapshot(readOnly), snapshot(open)]
        // The links are never walked: what they point at isn't in the backup's files.
        let listing = try storage.listing(id: id)
        #expect(listing.fileSizes.keys.sorted() == ["manifest.json"])
        if denyFolder {
            try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: nested.path)
            try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        }

        try storage.delete(id: id)

        #expect(!fileManager.fileExists(atPath: url.path))
        #expect(try storage.storedIDs().isEmpty)
        #expect(try [snapshot(readOnly), snapshot(open)] == before)
        let staging = URL(fileURLWithPath: folder.path + ".staging")
        #expect((try? fileManager.contentsOfDirectory(atPath: staging.path)) ?? [] == [])
    }

    @Test("makeRemovable never changes the mode of a link's target, given the link itself or one inside")
    func makeRemovableSkipsLinks() throws {
        defer { cleanUp() }
        let target = try outsideFolder("target", mode: 0o500, innerMode: 0o500)
        let before = try snapshot(target)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        FileBackupStorage.makeRemovable(link)

        #expect(try snapshot(target) == before)
    }

    @Test("A Backups folder that can be listed but not searched is a read failure, never an empty list (D214.1)")
    func rootNotSearchable() throws {
        defer { cleanUp() }
        let storage = try FileBackupStorage(folder: folder)
        let id = try backup(storage)
        let name = try #require(try fileManager.contentsOfDirectory(atPath: folder.path).first { $0 != "status.json" })
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        // Root can search it anyway.
        guard (try? fileManager.attributesOfItem(atPath: folder.appendingPathComponent(name).path)) == nil else {
            return
        }

        #expect(throws: BackupFileReadError.self) { try storage.storedIDs() }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        #expect(try storage.storedIDs() == [id])
    }
}
