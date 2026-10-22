import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// Tester finding 3 on 4c8b0b3: SwiftUI's `fileExporter` writes its own copy of the export to
/// `tmp/<uuid>/<file name>` in the app's container and leaves it there. Only files named the way an export is named
/// are removed, from `tmp` itself or a `<uuid>` folder in it; the folder goes too once it's empty.
@Suite("File backup storage: the save panel's copies in tmp")
struct FileBackupStorageSystemCopyTests {
    private let manager = FileManager.default

    private func scratch() throws -> URL {
        let url = manager.temporaryDirectory.appendingPathComponent(
            "system-tmp-\(UUID().uuidString)",
            isDirectory: true,
        )
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func file(_ folder: URL, _ path: String) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("copy".utf8).write(to: url)
        return url
    }

    @Test("At launch, the panel's copies go and nothing else in tmp does")
    func launchSweep() throws {
        let tmp = try scratch()
        let backups = try scratch()
        defer {
            try? manager.removeItem(at: tmp)
            try? manager.removeItem(at: backups)
        }
        let alone = UUID().uuidString
        let shared = UUID().uuidString
        let ours = [
            "\(alone)/little-orbit 2026-10-05 1000.littleorbit-backup",
            "\(shared)/little-orbit 2026-10-05 1000 2.littleorbit-backup",
            "little-orbit 2026-10-23 0136.littleorbit-backup",
            "\(UUID().uuidString)/\(UUID().uuidString).littleorbit-backup",
        ]
        let others = [
            "\(shared)/notes.txt",
            "my little-orbit backup.littleorbit-backup",
            "little-orbit 2026-10-05 1000.txt",
            "little-orbit 2026-10-05 1000.littleorbit-backup.download",
            "app.littleorbit.ios-Inbox/little-orbit 2026-10-05 1000.littleorbit-backup",
            "\(UUID().uuidString)/nested/little-orbit 2026-10-05 1000.littleorbit-backup",
        ]
        for path in ours + others {
            try file(tmp, path)
        }

        _ = try FileBackupStorage(folder: backups.appendingPathComponent("Backups"), systemTemporaryFolder: tmp)

        for path in ours {
            #expect(!manager.fileExists(atPath: tmp.appendingPathComponent(path).path), "\(path)")
        }
        for path in others {
            #expect(manager.fileExists(atPath: tmp.appendingPathComponent(path).path), "\(path)")
        }
        #expect(!manager.fileExists(atPath: tmp.appendingPathComponent(alone).path))
        #expect(manager.fileExists(atPath: tmp.appendingPathComponent(shared).path))
    }

    @Test("Without a tmp folder to sweep, nothing outside the store is touched")
    func noFolderNoSweep() throws {
        let tmp = try scratch()
        let backups = try scratch()
        defer {
            try? manager.removeItem(at: tmp)
            try? manager.removeItem(at: backups)
        }
        let copy = try file(tmp, "\(UUID().uuidString)/little-orbit 2026-10-05 1000.littleorbit-backup")
        let storage = try FileBackupStorage(folder: backups.appendingPathComponent("Backups"))
        storage.removeSystemExportCopies()
        #expect(manager.fileExists(atPath: copy.path))
    }
}
