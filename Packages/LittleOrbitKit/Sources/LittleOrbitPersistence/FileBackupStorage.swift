import Foundation
import LittleOrbitDomain

/// Backup folders in the app's own container: `Application Support/<bundle id>/Backups/<yyyy-MM-dd-HH-mm>/`, plus
/// `status.json` for the last failure and the restored state (D62, D195, D209).
///
/// - Each backup is one folder named by when it was made, in the device's time zone then, with `-2`, `-3` and so
///   on for a second backup in the same minute (D209). The name is never read back: a backup's identity is the
///   `id` in its manifest, and its date, order and month come from the manifest too. The list is always built from
///   the folders that exist, whatever they're called; there's no catalog to fall out of step (D195.3).
///   Folders named by a backup ID, from earlier builds, are read as before.
/// - A folder is built in the staging folder next to the Backups folder, `manifest.json` last, then renamed into
///   place, so only complete folders ever appear in the Backups folder (D195.6). A folder being deleted is renamed
///   into the staging folder first (L17). Only the staging folder is emptied at launch: a folder in the Backups
///   folder is never treated as a leftover, and one without a valid manifest is listed as damaged (D196.3, D197.4).
/// - A file that's byte-for-byte the same in the previous backup is copied from it with `FileManager.copyItem`,
///   which makes an APFS clone where the volume supports it and a plain copy elsewhere. Either way it's a separate
///   file with a link count of 1: no symlinks, no hard links (D195.1, L3, L6).
/// - Never in the App Group container (#52), so extensions can't read backups, and never uploaded.
/// - The folder stays in the system device backup (iCloud or computer) on every platform: until iCloud sync
///   exists, that's the only off-device copy (Kiran, D181). Revisiting this belongs with #21.
/// - On iOS and iPadOS every file and folder, the temporary ones included, gets the default data protection class,
///   `completeUntilFirstUserAuthentication`, so automatic backups keep working while the device is locked (D180,
///   R6). macOS relies on FileVault for protection at rest.
public final class FileBackupStorage: BackupStorage, @unchecked Sendable {
    public static let folderName = "Backups"
    static let statusName = "status.json"
    static let manifestName = BackupFormat.manifestPath

    let folder: URL
    private let staging: URL
    private let lock = NSLock()
    var fileManager: FileManager { .default }
    let timeZone: @Sendable () -> TimeZone
    /// The app's own `tmp`, where the save panel leaves its copies of an export; `nil` for none (Tester finding 3).
    let systemTemporaryFolder: URL?
    /// Each backup's folder name, by its ID, as the last listing or write found it.
    let names = BackupFolderNames()

    /// `folder` is created if missing. `staging`, by default `<folder>.staging` next to it on the same volume, is
    /// where folders are built and deleted; what an interrupted backup or cleanup left there is removed now.
    /// `timeZone` names new folders; it's the device's current one. `systemTemporaryFolder` is the app's `tmp`,
    /// swept for the save panel's copies of an export now and by `removeSystemExportCopies()`.
    public init(
        folder: URL,
        staging: URL? = nil,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        systemTemporaryFolder: URL? = nil,
    ) throws {
        self.folder = folder
        self.timeZone = timeZone
        self.systemTemporaryFolder = systemTemporaryFolder
        self.staging =
            staging
            ?? folder.deletingLastPathComponent()
            .appendingPathComponent("\(folder.lastPathComponent).staging", isDirectory: true)
        try prepare(folder)
        sweepLeftovers()
        removeSystemExportCopies()
    }

    /// `Application Support/<bundle id>/Backups`, next to the private store location (#52 fallback).
    public static func appDefault(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        fileManager: FileManager = .default,
    ) throws -> FileBackupStorage {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
        let base = StoreLocation.storeURL(applicationSupport: support, bundleIdentifier: bundleIdentifier)
            .deletingLastPathComponent()
        return try FileBackupStorage(
            folder: base.appendingPathComponent(folderName, isDirectory: true),
            systemTemporaryFolder: fileManager.temporaryDirectory,
        )
    }

    /// The folder of a backup. For tests and diagnostics only; the app never shows it.
    public func folderURL(_ id: UUID) -> URL {
        if names.name(of: id) == nil {
            _ = try? scan()
        }
        return folder.appendingPathComponent(names.name(of: id) ?? id.uuidString, isDirectory: true)
    }

    /// Every folder in the Backups folder, whatever it's called, with the ID it's known by: the manifest's `id`,
    /// else the name of a folder named by an ID (earlier builds), else one made from the name, so a folder with no
    /// readable manifest is still listed, as damaged (D196.3, D209). No date is ever read from a name.
    private func scan() throws -> [UUID] {
        var found: [UUID: String] = [:]
        var order: [UUID] = []
        let known = names.byName()
        for name in try fileManager.contentsOfDirectory(atPath: folder.path).sorted() where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            // A folder already known keeps its ID, so one whose manifest goes is still the same backup, now damaged.
            // One known only by its name's ID, because it couldn't be read, takes its manifest's ID once it can be,
            // so it lists again as the backup it is (D214.3).
            let fallback = BackupFolderNames.id(for: name)
            let previous = known[name].flatMap { $0 == fallback ? nil : $0 }
            var id = previous ?? BackupFolderNames.manifestID(in: url) ?? UUID(uuidString: name) ?? fallback
            if found[id] != nil {
                // A copy of another folder, manifest and all: listed on its own.
                id = BackupFolderNames.id(for: name)
            }
            found[id] = name
            order.append(id)
        }
        names.replace(with: found)
        return order
    }

    /// The staging folder. For tests only.
    var stagingURL: URL {
        staging
    }

    public func storedIDs() throws -> [UUID] {
        try locked { try scan() }
    }

    public func listing(id: UUID) throws -> BackupFolderListing {
        let url = folderURL(id)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BackupError.notFound
        }
        let base = url.standardizedFileURL.resolvingSymlinksInPath().path
        let (sizes, sizesKnown) = try Self.fileSizes(in: base)
        let manifestURL = url.appendingPathComponent(Self.manifestName)
        let manifest: Data? =
            sizes[Self.manifestName] == nil ? nil : try reading { try Data(contentsOf: manifestURL) }
        let created = try? fileManager.attributesOfItem(atPath: url.path)[.creationDate] as? Date
        return BackupFolderListing(manifest: manifest, fileSizes: sizes, createdAt: created, sizesKnown: sizesKnown)
    }

    /// Throws `notFound` when there's no such folder, and the underlying error for any other failed read.
    public func read(id: UUID) throws -> BackupSnapshotFiles {
        let url = folderURL(id)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BackupError.notFound
        }
        return try Self.readFolder(url)
    }

    /// Throws a read failure when the folder, or one inside it, can't be listed, so a check or a restore says the
    /// backup can't be read rather than finding its files missing and calling it damaged (D208.2, D214).
    public func files(id: UUID) throws -> any BackupFileReading {
        let url = folderURL(id)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BackupError.notFound
        }
        _ = try Self.fileSizes(in: url.standardizedFileURL.resolvingSymlinksInPath().path)
        return StoredBackupFolder(url)
    }

    public func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        try write(
            files,
            attachments: BackupAttachmentWrites(bytes: BackupLedgerAttachments(LedgerSnapshot())),
            id: id,
            cloningFrom: earlier,
        )
    }

    /// Each attachment file is cloned from `earlier` when it's unchanged, or streamed from its bytes into a new
    /// file in 1 MB chunks, so no attachment is ever held whole (B1).
    public func write(
        _ files: BackupSnapshotFiles,
        attachments: BackupAttachmentWrites,
        id: UUID,
        cloningFrom earlier: UUID?,
    ) throws {
        try locked {
            let temporary = staging.appendingPathComponent("\(id.uuidString).tmp", isDirectory: true)
            do {
                try prepare(staging)
                try prepare(folder)
                try writeFolder(files, attachments: attachments, to: temporary, cloningFrom: earlier.map(folderURL))
                try moveIntoPlace(temporary, id: id, manifest: files[Self.manifestName])
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw Self.isOutOfSpace(error) ? BackupError.notEnoughStorage : error
            }
        }
    }

    public func delete(id: UUID) throws {
        try locked {
            let url = folderURL(id)
            guard fileManager.fileExists(atPath: url.path) else {
                return
            }
            // Renamed first, in one step, so a cleanup killed midway leaves no part of a listed folder (L17).
            try prepare(staging)
            let deleting = staging.appendingPathComponent("\(id.uuidString).deleting", isDirectory: true)
            // A folder that can't be read is ours to delete all the same (D214). Moving a folder to another
            // parent needs write access to it, so a folder without it is given that first.
            if !fileManager.isWritableFile(atPath: url.path) {
                try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            try fileManager.moveItem(at: url, to: deleting)
            names.remove(id)
            Self.makeRemovable(deleting)
            try? fileManager.removeItem(at: deleting)
        }
    }

    /// No `status.json` is an empty status. One that can't be read, for lack of permission or an I/O error, throws
    /// a read failure (`BackupFileReadError`), so nothing is ever saved over it (R3). One that reads but doesn't
    /// decode is dropped as an empty status, and the next save replaces it: it's only a cache, so that loses the
    /// failure line, the skip-after-restore marker and what was known about each folder until the next full check.
    public func loadStatus() throws -> BackupStatus {
        try locked {
            let url = folder.appendingPathComponent(Self.statusName)
            guard fileManager.fileExists(atPath: url.path) else {
                return BackupStatus()
            }
            let data = try reading { try Data(contentsOf: url) }
            return (try? JSONDecoder().decode(BackupStatus.self, from: data)) ?? BackupStatus()
        }
    }

    public func saveStatus(_ status: BackupStatus) throws {
        try locked {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let url = folder.appendingPathComponent(Self.statusName)
            let temporary = staging.appendingPathComponent("\(UUID().uuidString).tmp")
            do {
                try prepare(staging)
                try prepare(folder)
                try encoder.encode(status).write(to: temporary, options: Self.writingOptions)
                if fileManager.fileExists(atPath: url.path) {
                    _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: url)
                }
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        }
    }

    /// Every regular file under `url` by relative path. Symlinks and anything else that isn't a regular file are
    /// left out, so a listed path that isn't a real file in the folder reads as missing.
    static func readFolder(_ url: URL) throws -> BackupSnapshotFiles {
        let base = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(atPath: base) else {
            throw BackupError.notFound
        }
        var files = BackupSnapshotFiles()
        while let relative = enumerator.nextObject() as? String {
            let path = base + "/" + relative
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                continue
            }
            files[relative] = try reading { try Data(contentsOf: URL(fileURLWithPath: path)) }
        }
        return files
    }

    /// Writes `files` and the attachment files under `destination`, `manifest.json` last. A file that's the same
    /// in `earlier` is cloned.
    private func writeFolder(
        _ files: BackupSnapshotFiles,
        attachments: BackupAttachmentWrites,
        to destination: URL,
        cloningFrom earlier: URL?,
    ) throws {
        try prepare(destination)
        try write(files.paths.filter { $0 != Self.manifestName }, of: files, to: destination, cloningFrom: earlier)
        for (path, id) in attachments.ids.sorted(by: { $0.key < $1.key }) {
            guard BackupFormat.isContained(path) else {
                throw BackupError.damaged
            }
            let url = destination.appendingPathComponent(path)
            try prepare(url.deletingLastPathComponent())
            if attachments.unchanged.contains(path), let source = earlier?.appendingPathComponent(path),
                Self.isRegularFile(source)
            {
                try Self.cloneOrCopy(from: source, to: url)
            } else {
                try Self.streamFile(to: url) { sink in
                    _ = try attachments.bytes.stream(id, through: sink)
                }
            }
        }
        try write(files.paths.filter { $0 == Self.manifestName }, of: files, to: destination, cloningFrom: earlier)
    }

    private func write(
        _ paths: [String],
        of files: BackupSnapshotFiles,
        to destination: URL,
        cloningFrom earlier: URL?,
    ) throws {
        for path in paths {
            guard BackupFormat.isContained(path), let data = files[path] else {
                throw BackupError.damaged
            }
            let url = destination.appendingPathComponent(path)
            try prepare(url.deletingLastPathComponent())
            if let source = earlier?.appendingPathComponent(path), path != Self.manifestName,
                Self.hasSameBytes(source, as: data)
            {
                try Self.cloneOrCopy(from: source, to: url)
            } else {
                try data.write(to: url, options: Self.writingOptions)
            }
        }
    }

    /// An APFS clone of `source` where the volume supports one, a plain copy otherwise. Never a link (L6).
    static func cloneOrCopy(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func hasSameBytes(_ url: URL, as data: Data) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            (attributes[.size] as? NSNumber)?.intValue == data.count
        else {
            return false
        }
        return (try? Data(contentsOf: url)) == data
    }

    /// Creates a folder if it's missing, with the default data protection class on iOS. It isn't excluded from the
    /// device backup (D181).
    func prepare(_ url: URL) throws {
        #if os(iOS) || os(watchOS)
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        #else
            let attributes: [FileAttributeKey: Any]? = nil
        #endif
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
    }

    /// Empties the staging folder: what an interrupted backup or cleanup left behind. Runs once, before any write
    /// of this launch. Nothing in the Backups folder is touched (D197.4).
    private func sweepLeftovers() {
        let names = (try? fileManager.contentsOfDirectory(atPath: staging.path)) ?? []
        for name in names {
            try? fileManager.removeItem(at: staging.appendingPathComponent(name))
        }
    }

    static var writingOptions: Data.WritingOptions {
        #if os(iOS) || os(watchOS)
            [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.withoutOverwriting]
        #endif
    }

    static func isOutOfSpace(_ error: any Error) -> Bool {
        if let backup = error as? BackupError {
            return backup == .notEnoughStorage
        }
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOutOfSpace(underlying)
        }
        return false
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// One stored backup folder, read a file at a time (B1.2). Only real regular files inside the folder count: a
/// path through a symlink, or to anything that isn't a regular file, reads as missing, the same as `readFolder`.
struct StoredBackupFolder: BackupFileReading {
    /// The size of each chunk a streamed file is read in.
    static let chunkSize = 1 << 20

    private let base: String

    init(_ url: URL) {
        base = url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    func data(at path: String) throws -> Data? {
        guard let url = regularFile(path) else {
            return nil
        }
        // Mapped where the system can, so a large attachment isn't copied into memory just to be read.
        return try reading { try Data(contentsOf: url, options: .mappedIfSafe) }
    }

    func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        guard let url = regularFile(path) else {
            return false
        }
        try FileChunkReader.stream(url, chunkSize: Self.chunkSize, through: body)
        return true
    }

    private func regularFile(_ path: String) -> URL? {
        guard BackupFormat.isContained(path) else {
            return nil
        }
        let url = URL(fileURLWithPath: base + "/" + path).standardizedFileURL
        guard url.resolvingSymlinksInPath().path == url.path,
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular
        else {
            return nil
        }
        return url
    }
}
