import Foundation

/// Copies a SQLite store and its `-wal` and `-shm` into a scratch folder without tearing, for the read-only
/// contents probe (`StoreContentsProbe`). Kept apart from SwiftData so it is tested on Linux.
enum StoreScratchCopy {
    /// Prefix of every scratch folder, so leftovers from a crashed probe can be found and removed. It names the
    /// app because the unsandboxed Mac app shares its temporary folder with the user's other apps, and the sweep
    /// must never touch their folders.
    static let folderPrefix = "littleorbit-store-probe-"
    /// The SQLite companion files copied with the store, so a write that is still in the WAL is counted.
    static let companionSuffixes = ["-wal", "-shm"]
    /// A leftover scratch folder older than this is removed at the start of a probe. Newer ones may belong to a
    /// probe that is still running in another process or test.
    static let leftoverAge: TimeInterval = 5 * 60

    enum Failure: String, Error, Equatable {
        /// The store or a companion couldn't be copied, for example on a full disk.
        case copyFailed
        /// The store or its `-wal` changed while it was copied, twice in a row.
        case changedDuringCopy
    }

    /// One file's identity, size and modification date, or `nil` when it doesn't exist.
    struct FileFingerprint: Equatable {
        var fileNumber: Int?
        var size: Int?
        var modified: Date?
    }

    /// The store's and `-wal`'s fingerprints. A checkpoint or WAL restart changes at least one of them.
    static func fingerprint(of storeURL: URL, fileManager: FileManager) -> [FileFingerprint?] {
        [storeURL, companion(of: storeURL, suffix: "-wal")]
            .map { url in
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
                    return nil
                }
                return FileFingerprint(
                    fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.intValue,
                    size: (attributes[.size] as? NSNumber)?.intValue,
                    modified: attributes[.modificationDate] as? Date,
                )
            }
    }

    /// Copies `storeURL` and its companions into `scratch` and returns the copy's URL. The store and `-wal` are
    /// fingerprinted before and after; if either changed, the copy is retried once, and a second change throws
    /// `changedDuringCopy`, which the probe counts as holding data. `afterMainFile` runs between copying the main
    /// file and the companions, for tests.
    static func copy(
        _ storeURL: URL,
        into scratch: URL,
        fileManager: FileManager = .default,
        afterMainFile: () -> Void = {},
    ) throws(Failure) -> URL {
        let copy = scratch.appendingPathComponent(storeURL.lastPathComponent, isDirectory: false)
        for _ in 0..<2 {
            let before = fingerprint(of: storeURL, fileManager: fileManager)
            do {
                try? fileManager.removeItem(at: scratch)
                try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
                try fileManager.copyItem(at: storeURL, to: copy)
                afterMainFile()
                for suffix in companionSuffixes {
                    let source = companion(of: storeURL, suffix: suffix)
                    if fileManager.fileExists(atPath: source.path) {
                        try fileManager.copyItem(at: source, to: companion(of: copy, suffix: suffix))
                    }
                }
            } catch {
                throw .copyFailed
            }
            if fingerprint(of: storeURL, fileManager: fileManager) == before {
                return copy
            }
        }
        throw .changedDuringCopy
    }

    /// A new, uniquely named scratch folder URL in `parent`. The folder isn't created.
    static func newScratchFolder(in parent: URL) -> URL {
        parent.appendingPathComponent(folderPrefix + UUID().uuidString, isDirectory: true)
    }

    /// Removes scratch folders in `parent` left by a probe that crashed, if they are older than `leftoverAge`.
    /// Only names starting with `folderPrefix` are ever matched.
    static func removeLeftovers(in parent: URL, now: Date = Date(), fileManager: FileManager = .default) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let items = try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: keys) else {
            return
        }
        for item in items where item.lastPathComponent.hasPrefix(folderPrefix) {
            let modified = (try? item.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > leftoverAge {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private static func companion(of url: URL, suffix: String) -> URL {
        URL(fileURLWithPath: url.path + suffix)
    }
}
