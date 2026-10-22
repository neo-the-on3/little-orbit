import Foundation
import LittleOrbitDomain

/// Backup files in the app's own container: `Application Support/<bundle id>/Backups/<id>.littleorbit-backup`,
/// plus `catalog.json` for the list (D62).
///
/// - Never in the App Group container (#52), so extensions can't read backups, and never uploaded.
/// - Files are stored by ID, never by display name (D173.11).
/// - On iOS and iPadOS the folder is excluded from the system device backup (iCloud or computer), so backups are
///   never uploaded and don't take iCloud storage twice (D179.1). The live store stays in the device backup.
///   macOS leaves the folder to Time Machine, and relies on FileVault for protection at rest.
/// - On iOS each file gets `completeUnlessOpen` data protection: unreadable while the device is locked, except a
///   backup already being written when the device locks.
/// - Every write goes to a temporary file first and is moved into place, so a full disk or a crash leaves no
///   partial backup (D62).
public final class FileBackupStorage: BackupStorage, @unchecked Sendable {
    public static let folderName = "Backups"
    static let catalogName = "catalog.json"

    /// Whether the platform excludes the Backups folder from the device backup (D179.1).
    public static var excludesFromDeviceBackupByDefault: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    private let folder: URL
    private let excludesFromDeviceBackup: Bool
    private let lock = NSLock()

    /// `folder` is created if missing. `excludesFromDeviceBackup` sets the exclude-from-backup flag on it, again
    /// whenever the folder has to be recreated.
    public init(folder: URL, excludesFromDeviceBackup: Bool = FileBackupStorage.excludesFromDeviceBackupByDefault)
        throws
    {
        self.folder = folder
        self.excludesFromDeviceBackup = excludesFromDeviceBackup
        try prepareFolder()
        sweepTemporaryFiles()
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
        return try FileBackupStorage(folder: base.appendingPathComponent(folderName, isDirectory: true))
    }

    public func loadCatalog() throws -> BackupCatalog {
        try locked {
            let url = folder.appendingPathComponent(Self.catalogName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return BackupCatalog()
            }
            guard let catalog = try? JSONDecoder().decode(BackupCatalog.self, from: Data(contentsOf: url)) else {
                throw BackupError.catalogUnreadable
            }
            return catalog
        }
    }

    public func saveCatalog(_ catalog: BackupCatalog) throws {
        try locked {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            _ = try writeAtomically(try encoder.encode(catalog), to: folder.appendingPathComponent(Self.catalogName))
        }
    }

    public func write(_ data: Data, id: UUID) throws -> Int64 {
        try locked {
            try writeAtomically(data, to: fileURL(id))
        }
    }

    public func read(id: UUID) throws -> Data {
        do {
            return try Data(contentsOf: fileURL(id))
        } catch {
            throw BackupError.notFound
        }
    }

    public func delete(id: UUID) throws {
        try locked {
            let url = fileURL(id)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    public func storedIDs() throws -> [UUID] {
        try locked {
            try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0.hasSuffix(".\(BackupFormat.fileExtension)") }
                .compactMap { UUID(uuidString: String($0.dropLast(BackupFormat.fileExtension.count + 1))) }
        }
    }

    /// The stored file for a backup. For tests and diagnostics only; the app never shows it.
    public func fileURL(_ id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).\(BackupFormat.fileExtension)")
    }

    /// Creates the folder if it's missing and keeps it out of the device backup where that applies.
    private func prepareFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard excludesFromDeviceBackup else {
            return
        }
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Removes temporary files a crash left behind mid-write. Runs once, before any write of this launch.
    private func sweepTemporaryFiles() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(".") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func writeAtomically(_ data: Data, to url: URL) throws -> Int64 {
        try prepareFolder()
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: Self.writingOptions)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw Self.isOutOfSpace(error) ? BackupError.notEnoughStorage : error
        }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.int64Value ?? Int64(data.count)
    }

    private static var writingOptions: Data.WritingOptions {
        #if os(iOS) || os(watchOS)
            [.withoutOverwriting, .completeFileProtectionUnlessOpen]
        #else
            [.withoutOverwriting]
        #endif
    }

    static func isOutOfSpace(_ error: any Error) -> Bool {
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
