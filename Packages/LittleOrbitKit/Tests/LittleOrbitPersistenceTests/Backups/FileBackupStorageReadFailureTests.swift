import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// Tech Architect on 8a43e74 (N3, R3): a `status.json` or a backup folder that can't be read is a read failure,
/// thrown, never an empty status or a folder with nothing in it. A missing `status.json` is still an empty status,
/// and one that reads but doesn't decode is still dropped.
@Suite("File backup storage: status and folders that can't be read (R3)", .serialized, .timeLimit(.minutes(2)))
struct FileBackupStorageReadFailureTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "backups-\(UUID().uuidString)",
            isDirectory: true,
        )
    }

    private func remove(_ folder: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }

    /// `url` set to `mode`; `false`, with the mode put back, when this process can read it anyway (as root can).
    private func deny(_ url: URL, mode: Int = 0) throws -> Bool {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        let readable =
            isDirectory(url)
            ? (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            : FileManager.default.isReadableFile(atPath: url.path)
        if readable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return false
        }
        return true
    }

    private func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static let saved = BackupStatus(lastFailure: .notEnoughStorage, restoredFingerprint: "abc")

    @Test("A status.json it may not read throws a read failure, and its bytes stay as they were")
    func statusDenied() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        try storage.saveStatus(Self.saved)
        let url = folder.appendingPathComponent("status.json")
        let bytes = try Data(contentsOf: url)
        guard try deny(url) else {
            return
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        #expect(throws: BackupFileReadError.self) { try storage.loadStatus() }

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try storage.loadStatus() == Self.saved)
    }

    @Test("A status.json that can't be read as a file (here a folder, which root can't read either) throws")
    func statusNotAFile() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("status.json"),
            withIntermediateDirectories: false,
        )
        #expect(throws: BackupFileReadError.self) { try storage.loadStatus() }
    }

    @Test("A missing status.json is an empty status; one that reads but doesn't decode is dropped as empty")
    func statusMissingOrUndecodable() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        #expect(try storage.loadStatus() == BackupStatus())
        try Data("not json".utf8).write(to: folder.appendingPathComponent("status.json"))
        #expect(try storage.loadStatus() == BackupStatus())
    }

    @Test("A backup folder whose contents can't be listed throws a read failure, not a folder with no manifest")
    func folderDenied() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(BackupSnapshotFiles(["manifest.json": Data("{}".utf8)]), id: id, cloningFrom: nil)
        let url = storage.folderURL(id)
        guard try deny(url) else {
            return
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }

        #expect(throws: BackupFileReadError.self) { try storage.listing(id: id) }
    }

    @Test("A folder inside a backup that can't be listed throws a read failure too")
    func subfolderDenied() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(
            BackupSnapshotFiles(["manifest.json": Data("{}".utf8), "accounts/A/2026.json": Data("year".utf8)]),
            id: id,
            cloningFrom: nil,
        )
        let accounts = storage.folderURL(id).appendingPathComponent("accounts", isDirectory: true)
        guard try deny(accounts) else {
            return
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: accounts.path) }

        #expect(throws: BackupFileReadError.self) { try storage.listing(id: id) }
    }

    @Test("A readable folder lists every regular file with its size, as before")
    func folderReadable() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(
            BackupSnapshotFiles(["manifest.json": Data("{}".utf8), "accounts/A/2026.json": Data("year".utf8)]),
            id: id,
            cloningFrom: nil,
        )
        let listing = try storage.listing(id: id)
        #expect(listing.fileSizes == ["manifest.json": 2, "accounts/A/2026.json": 4])
        #expect(listing.manifest == Data("{}".utf8))
        #expect(listing.sizesKnown)
    }

    @Test("Reading a backup whose folder can't be listed throws a read failure, so it's never called damaged (D208.2)")
    func filesDenied() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(
            BackupSnapshotFiles(["manifest.json": Data("{}".utf8), "accounts/A/2026.json": Data("year".utf8)]),
            id: id,
            cloningFrom: nil,
        )
        let accounts = storage.folderURL(id).appendingPathComponent("accounts", isDirectory: true)
        guard try deny(accounts) else {
            return
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: accounts.path) }

        #expect(throws: BackupFileReadError.self) { try storage.files(id: id) }
    }

    @Test("Delete removes a backup folder that can't be read, inner folders included (D214)")
    func deleteDenied() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(
            BackupSnapshotFiles(["manifest.json": Data("{}".utf8), "accounts/A/2026.json": Data("year".utf8)]),
            id: id,
            cloningFrom: nil,
        )
        let url = storage.folderURL(id)
        let accounts = url.appendingPathComponent("accounts", isDirectory: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: accounts.path)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: accounts.path)
        }

        try storage.delete(id: id)

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try storage.storedIDs().isEmpty)
        let staging = URL(fileURLWithPath: folder.path + ".staging")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? [] == [])
    }

    @Test("A folder's creation date is read without reading the folder, where the platform reports one (D214.3)")
    func creationDate() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(BackupSnapshotFiles(["manifest.json": Data("{}".utf8)]), id: id, cloningFrom: nil)
        let url = storage.folderURL(id)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        // Read after the chmod: on Linux, creationDate follows ctime, which the chmod changes.
        let expected = try FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date

        #expect(storage.folderCreationDate(id: id) == expected)
        #expect(storage.folderCreationDate(id: UUID()) == nil)
    }
}
