import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// D62: backup files stay in the app's own folder, by ID, written whole or not at all.
@Suite("File backup storage")
struct FileBackupStorageTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "backups-\(UUID().uuidString)",
            isDirectory: true,
        )
    }

    @Test("Files are stored by ID, read back and deleted")
    func roundTrip() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        let size = try storage.write(Data("backup".utf8), id: id)
        #expect(size == 6)
        #expect(storage.fileURL(id).lastPathComponent == "\(id.uuidString).littleorbit-backup")
        #expect(try storage.read(id: id) == Data("backup".utf8))
        try storage.delete(id: id)
        #expect(throws: BackupError.notFound) { try storage.read(id: id) }
    }

    @Test("No temporary files are left behind")
    func noLeftovers() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FileBackupStorage(folder: folder)
        _ = try storage.write(Data("one".utf8), id: UUID())
        try storage.saveCatalog(BackupCatalog())
        try storage.saveCatalog(BackupCatalog(lastFailure: .notEnoughStorage))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(!names.contains { $0.hasSuffix(".tmp") })
        #expect(names.count == 2)
    }

    @Test("The catalog round-trips and starts empty")
    func catalog() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FileBackupStorage(folder: folder)
        #expect(try storage.loadCatalog() == BackupCatalog())
        let record = BackupRecord(kind: .manual, createdAt: Date(timeIntervalSince1970: 1_792_640_525.5), nameIndex: 2)
        let catalog = BackupCatalog(records: [record], restoredFingerprint: "abc")
        try storage.saveCatalog(catalog)
        #expect(try FileBackupStorage(folder: folder).loadCatalog() == catalog)
    }

    @Test("The default folder is Application Support/<bundle id>/Backups, never the App Group (#52)")
    func appDefault() throws {
        let storage = try FileBackupStorage.appDefault(bundleIdentifier: "app.littleorbit.tests")
        let url = storage.fileURL(UUID()).deletingLastPathComponent()
        #expect(url.lastPathComponent == "Backups")
        #expect(url.deletingLastPathComponent().lastPathComponent == "app.littleorbit.tests")
        #expect(!url.path.contains("Group Containers"))
    }

    @Test("Out-of-space errors are recognised, also when wrapped")
    func outOfSpace() {
        #expect(FileBackupStorage.isOutOfSpace(CocoaError(.fileWriteOutOfSpace)))
        #expect(FileBackupStorage.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: 512,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))],
        )
        #expect(FileBackupStorage.isOutOfSpace(wrapped))
        #expect(!FileBackupStorage.isOutOfSpace(CocoaError(.fileNoSuchFile)))
    }

    @Test("An unreadable catalog is reported so the service can rebuild it (N3)")
    func unreadableCatalog() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FileBackupStorage(folder: folder)
        try Data("{not json".utf8).write(to: folder.appendingPathComponent("catalog.json"))
        #expect(throws: BackupError.catalogUnreadable) { try storage.loadCatalog() }
    }

    @Test("Stored IDs come from the backup files only")
    func storedIDs() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        _ = try storage.write(Data("x".utf8), id: id)
        try storage.saveCatalog(BackupCatalog())
        try Data("note".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        #expect(try storage.storedIDs() == [id])
    }

    @Test("Temporary files left by a crash are swept at launch (N3)")
    func sweep() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try FileBackupStorage(folder: folder)
        let stray = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        try Data("partial".utf8).write(to: stray)
        _ = try FileBackupStorage(folder: folder)
        #expect(!FileManager.default.fileExists(atPath: stray.path))
    }

    @Test("Only iOS and iPadOS exclude the folder from the device backup by default (D179.1)")
    func platformDefault() {
        #if os(iOS)
            #expect(FileBackupStorage.excludesFromDeviceBackupByDefault)
        #else
            #expect(!FileBackupStorage.excludesFromDeviceBackupByDefault)
        #endif
    }

    #if canImport(Darwin)
        @Test("The folder is excluded from the device backup, also after it's recreated (D179.1)")
        func excludedFromDeviceBackup() throws {
            let folder = folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let storage = try FileBackupStorage(folder: folder, excludesFromDeviceBackup: true)
            #expect(try isExcluded(folder))

            try FileManager.default.removeItem(at: folder)
            _ = try storage.write(Data("backup".utf8), id: UUID())
            #expect(try isExcluded(folder))
        }

        @Test("Without the flag the folder stays in the device backup (macOS, Time Machine)")
        func notExcluded() throws {
            let folder = folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            _ = try FileBackupStorage(folder: folder, excludesFromDeviceBackup: false)
            #expect(try !isExcluded(folder))
        }

        private func isExcluded(_ folder: URL) throws -> Bool {
            var url = folder
            url.removeAllCachedResourceValues()
            return try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        }
    #endif
}
