import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// D62 and D195: one folder per backup, by ID, complete or not there at all.
@Suite("File backup storage")
struct FileBackupStorageTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "backups-\(UUID().uuidString)",
            isDirectory: true,
        )
    }

    /// Removes a test's Backups folder and its staging folder next to it.
    private func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }

    private func snapshot(_ year: String = "2026") -> BackupSnapshotFiles {
        BackupSnapshotFiles([
            "manifest.json": Data("{\"m\":1}".utf8),
            "shared.json": Data("shared".utf8),
            "transfers/2026.json": Data("transfers".utf8),
            "accounts/A/\(year).json": Data("year".utf8),
            "attachments/B": Data([0xFF, 0xD8]),
        ])
    }

    private func names(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test("A backup is one folder named by its ID, read back and deleted whole (L1)")
    func roundTrip() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(snapshot(), id: id, cloningFrom: nil)
        #expect(try names(folder) == [id.uuidString])
        #expect(try storage.read(id: id) == snapshot())
        let listing = try storage.listing(id: id)
        #expect(listing.manifest == Data("{\"m\":1}".utf8))
        #expect(listing.fileSizes["accounts/A/2026.json"] == 4)
        #expect(listing.fileSizes.count == 5)
        #expect(try storage.storedIDs() == [id])
        try storage.delete(id: id)
        #expect(throws: BackupError.notFound) { try storage.read(id: id) }
        #expect(throws: BackupError.notFound) { try storage.listing(id: id) }
        #expect(try names(folder).isEmpty)
        #expect(try names(storage.stagingURL).isEmpty)
    }

    @Test("No temporary folder is left behind")
    func noLeftovers() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(snapshot(), id: id, cloningFrom: nil)
        try storage.saveStatus(BackupStatus())
        try storage.saveStatus(BackupStatus(lastFailure: .notEnoughStorage))
        #expect(try names(folder) == [id.uuidString, "status.json"].sorted())
        #expect(try names(storage.stagingURL).isEmpty)
    }

    @Test("Every folder is listed whatever its name, with a manifest or not; files aren't (D196.3, L29, D209)")
    func storedIDs() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(snapshot(), id: id, cloningFrom: nil)
        try storage.saveStatus(BackupStatus())
        let noManifestID = UUID()
        let noManifest = folder.appendingPathComponent(noManifestID.uuidString)
        try FileManager.default.createDirectory(at: noManifest, withIntermediateDirectories: true)
        try Data("shared".utf8).write(to: noManifest.appendingPathComponent("shared.json"))
        try Data("note".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try Data("old".utf8).write(to: folder.appendingPathComponent(UUID().uuidString))
        let lowercased = UUID()
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(lowercased.uuidString.lowercased()),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Copied by hand"),
            withIntermediateDirectories: true,
        )
        let ids = try storage.storedIDs()
        #expect(ids.count == 4)
        #expect(Set(ids).isSuperset(of: [id, noManifestID, lowercased]))
        #expect(try storage.storedIDs() == ids)
        let listing = try storage.listing(id: noManifestID)
        #expect(listing.manifest == nil)
        #expect(listing.fileSizes == ["shared.json": 6])
    }

    @Test("A folder deleted by hand just leaves the list (L5)")
    func deletedByHand() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let kept = UUID()
        let gone = UUID()
        try storage.write(snapshot(), id: kept, cloningFrom: nil)
        try storage.write(snapshot(), id: gone, cloningFrom: kept)
        try FileManager.default.removeItem(at: storage.folderURL(gone))
        #expect(try storage.storedIDs() == [kept])
        #expect(try storage.read(id: kept) == snapshot())
    }

    @Test("Unchanged files are cloned from the earlier backup; each folder stands alone (L6)")
    func clones() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let first = UUID()
        let second = UUID()
        try storage.write(snapshot(), id: first, cloningFrom: nil)
        try storage.write(snapshot("2027"), id: second, cloningFrom: first)
        #expect(try storage.read(id: second) == snapshot("2027"))

        // Changing a file in one folder never changes the other's.
        let shared = storage.folderURL(first).appendingPathComponent("shared.json")
        try Data("changed".utf8).write(to: shared)
        #expect(try storage.read(id: second)["shared.json"] == Data("shared".utf8))

        // Deleting the earlier folder leaves the later one whole.
        try storage.delete(id: first)
        #expect(try storage.read(id: second) == snapshot("2027"))
    }

    @Test("Every file is a regular file with one link; no symlinks, no hard links (L3)")
    func noLinks() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let first = UUID()
        let second = UUID()
        try storage.write(snapshot(), id: first, cloningFrom: nil)
        try storage.write(snapshot(), id: second, cloningFrom: first)
        for id in [first, second] {
            let base = storage.folderURL(id).path
            let enumerator = try #require(FileManager.default.enumerator(atPath: base))
            while let relative = enumerator.nextObject() as? String {
                let attributes = try FileManager.default.attributesOfItem(atPath: base + "/" + relative)
                let type = attributes[.type] as? FileAttributeType
                #expect(type == .typeRegular || type == .typeDirectory)
                if type == .typeRegular {
                    #expect((attributes[.referenceCount] as? NSNumber)?.intValue == 1)
                }
            }
        }
    }

    @Test("The clone helper makes a separate file")
    func cloneHelper() throws {
        let folder = folder()
        defer { remove(folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("a")
        let copy = folder.appendingPathComponent("b")
        try Data("one".utf8).write(to: source)
        try FileBackupStorage.cloneOrCopy(from: source, to: copy)
        try Data("two".utf8).write(to: source)
        #expect(try Data(contentsOf: copy) == Data("one".utf8))
        try FileManager.default.removeItem(at: source)
        #expect(try Data(contentsOf: copy) == Data("one".utf8))
    }

    @Test("A failed write leaves no folder (L15)")
    func failedWrite() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        var bad = snapshot()
        bad["../escape.json"] = Data("x".utf8)
        let id = UUID()
        #expect(throws: (any Error).self) { try storage.write(bad, id: id, cloningFrom: nil) }
        #expect(try names(folder).isEmpty)
        #expect(try storage.storedIDs().isEmpty)
    }

    @Test("Folders are built outside the Backups folder; only the staging folder is emptied at launch (L15, D197.4)")
    func sweep() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let kept = UUID()
        try storage.write(snapshot(), id: kept, cloningFrom: nil)
        #expect(storage.stagingURL.deletingLastPathComponent() == folder.deletingLastPathComponent())
        #expect(!storage.stagingURL.path.hasPrefix(folder.path + "/"))
        for name in ["\(UUID().uuidString).tmp", "\(UUID().uuidString).deleting", "\(UUID().uuidString)"] {
            let url = storage.stagingURL.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url.appendingPathComponent("manifest.json"))
        }
        // A folder in the Backups folder without a valid manifest is a damaged backup, never a leftover.
        let damaged = UUID()
        try FileManager.default.createDirectory(
            at: storage.folderURL(damaged),
            withIntermediateDirectories: true,
        )
        let relaunched = try FileBackupStorage(folder: folder)
        #expect(Set(try relaunched.storedIDs()) == [kept, damaged])
        #expect(try names(relaunched.stagingURL).isEmpty)
        #expect(try names(folder) == [kept.uuidString, damaged.uuidString].sorted())
    }

    @Test("Files the folder holds as symlinks are never read (L3)")
    func symlinksAreNotRead() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        try storage.write(snapshot(), id: id, cloningFrom: nil)
        let outside = folder.appendingPathComponent("outside.txt")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: storage.folderURL(id).appendingPathComponent("extra.json"),
            withDestinationURL: outside,
        )
        #expect(try storage.read(id: id)["extra.json"] == nil)
    }

    @Test("A folder is read a file at a time: streamed in chunks, or whole; links read as missing (B1.2, L3)")
    func fileByFile() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        let id = UUID()
        var files = snapshot()
        let large = Data((0..<(StoredBackupFolder.chunkSize * 2 + 17)).map { UInt8($0 % 253) })
        files["attachments/large"] = large
        try storage.write(files, id: id, cloningFrom: nil)
        let reader = try storage.files(id: id)
        var chunks: [Int] = []
        var streamed = Data()
        #expect(
            try reader.stream("attachments/large") {
                chunks.append($0.count)
                streamed.append(contentsOf: $0)
            }
        )
        #expect(streamed == large)
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0 <= StoredBackupFolder.chunkSize })
        #expect(try reader.data(at: "manifest.json") == files["manifest.json"])
        #expect(try reader.data(at: "missing.json") == nil)
        #expect(try reader.data(at: "../outside.json") == nil)

        let outside = folder.appendingPathComponent("outside.txt")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: storage.folderURL(id).appendingPathComponent("extra.json"),
            withDestinationURL: outside,
        )
        try FileManager.default.createSymbolicLink(
            at: storage.folderURL(id).appendingPathComponent("linked"),
            withDestinationURL: folder,
        )
        #expect(try reader.data(at: "extra.json") == nil)
        #expect(try !reader.stream("extra.json") { _ in })
        #expect(try reader.data(at: "linked/outside.txt") == nil)
        #expect(throws: BackupError.notFound) { try storage.files(id: UUID()) }
    }

    @Test("The status round-trips and starts empty")
    func status() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        #expect(try storage.loadStatus() == BackupStatus())
        let known = BackupRecord(kind: .automatic, createdAt: Date(timeIntervalSince1970: 1_792_640_525))
        let status = BackupStatus(
            lastFailure: .notEnoughStorage,
            restoredFingerprint: "abc",
            known: [known.id: known],
        )
        try storage.saveStatus(status)
        #expect(try FileBackupStorage(folder: folder).loadStatus() == status)
        // A status from before the cache still reads.
        try Data(#"{"restoredFingerprint":"abc"}"#.utf8)
            .write(to: folder.appendingPathComponent("status.json"))
        #expect(try storage.loadStatus() == BackupStatus(restoredFingerprint: "abc"))
    }

    @Test("The default folder is Application Support/<bundle id>/Backups, never the App Group (#52)")
    func appDefault() throws {
        let storage = try FileBackupStorage.appDefault(bundleIdentifier: "app.littleorbit.tests")
        let url = storage.folderURL(UUID()).deletingLastPathComponent()
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

    @Test("A missing folder is notFound; a manifest that isn't a regular file isn't read (L3, L37)")
    func readErrors() throws {
        let folder = folder()
        defer { remove(folder) }
        let storage = try FileBackupStorage(folder: folder)
        #expect(throws: BackupError.notFound) { try storage.read(id: UUID()) }
        #expect(throws: BackupError.notFound) { try storage.listing(id: UUID()) }
        let id = UUID()
        let manifest = storage.folderURL(id).appendingPathComponent("manifest.json")
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: true)
        #expect(try storage.listing(id: id).manifest == nil)
    }

    @Test("On iOS the files use the default Data Protection class, not completeUnlessOpen (D180, R2, R6, S32)")
    func protectionClass() {
        #if os(iOS)
            #expect(FileBackupStorage.writingOptions.contains(.completeFileProtectionUntilFirstUserAuthentication))
            #expect(!FileBackupStorage.writingOptions.contains(.completeFileProtectionUnlessOpen))
            #expect(!FileBackupStorage.writingOptions.contains(.completeFileProtection))
        #else
            #expect(FileBackupStorage.writingOptions == [.withoutOverwriting])
        #endif
    }

    #if canImport(Darwin)
        @Test("The folders and files stay in the device backup, also after it's recreated (D181, S83)")
        func notExcludedFromDeviceBackup() throws {
            let folder = folder()
            defer { remove(folder) }
            let storage = try FileBackupStorage(folder: folder)
            #expect(try !isExcluded(folder))
            #expect(!hasExcludeAttribute(folder))

            try FileManager.default.removeItem(at: folder)
            let id = UUID()
            try storage.write(snapshot(), id: id, cloningFrom: nil)
            try storage.saveStatus(BackupStatus())
            let backup = storage.folderURL(id)
            for url in [
                folder, backup, backup.appendingPathComponent("manifest.json"),
                backup.appendingPathComponent("accounts/A/2026.json"), folder.appendingPathComponent("status.json"),
            ] {
                #expect(try !isExcluded(url))
                #expect(!hasExcludeAttribute(url))
            }
        }

        private func isExcluded(_ url: URL) throws -> Bool {
            var url = url
            url.removeAllCachedResourceValues()
            return try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        }

        /// The extended attribute `isExcludedFromBackup` sets, which S83 checks with `xattr -l`.
        private func hasExcludeAttribute(_ url: URL) -> Bool {
            getxattr(url.path, "com.apple.metadata:com_apple_backup_excludeItem", nil, 0, 0, 0) >= 0
        }
    #endif
}
