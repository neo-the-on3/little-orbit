import Foundation

/// One entry of an exported backup archive, as read without extracting anything.
public struct BackupArchiveEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A regular file, with its bytes when they were read, or `nil` when only the header was.
        case file(Data?)
        case directory
        /// A symbolic link to `target`.
        case symbolicLink(target: String)
        /// A hard link to the entry at `target`.
        case hardLink(target: String)
        /// Anything else: a device, a FIFO, a socket, or an entry the archive reader refused to read.
        case other
    }

    /// The path as stored in the archive.
    public var path: String
    public var kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

/// Where an archive is read from: a picked file, read where it is, or bytes already in memory.
public enum BackupArchiveSource: Equatable, Sendable {
    /// Streamed from the file, never loaded whole (B1.1).
    case file(URL)
    case data(Data)
}

/// What a read does with one regular file's bytes.
public enum BackupArchiveRead {
    /// Only the header: the entry comes back as `.file(nil)`.
    case skip
    /// The bytes, in the entry.
    case data
    /// The bytes handed to the closure in chunks, in order, never held whole. The entry comes back as `.file(nil)`.
    case stream((UnsafeRawBufferPointer) -> Void)
}

/// The single `.littleorbit-backup` file an export saves: one backup folder in an uncompressed Apple Archive
/// (D195a.1). On Apple platforms `LittleOrbitPersistence` implements it with AppleArchive; it isn't available
/// elsewhere. Nothing is ever extracted or written to disk.
public protocol BackupArchiving: Sendable {
    /// One archive holding every file of `files` at its relative path, in memory. Tests and crafted archives use
    /// it; an export writes to a file with the method below.
    func archive(_ files: BackupSnapshotFiles) throws -> Data
    /// A new archive file at `url`, which mustn't exist: `files` in order, each with a header of its listed size,
    /// then its bytes streamed from `folder` in chunks, never held whole (B2). A file that isn't exactly its listed
    /// size throws `damaged`. Errors from `folder` are rethrown; the caller removes what was written.
    func archive(_ files: [BackupArchiveFile], from folder: any BackupFileReading, to url: URL) throws
    /// The entries of `archive`, in order, in one pass, extracting nothing. `reading` says, for each regular file
    /// by its stored path, whether to skip its bytes, keep them, or stream them. Throws `BackupError.damaged` for
    /// anything that isn't an archive, and the underlying error when the file can't be read at all.
    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry]
}

extension BackupArchiving {
    /// The entries of `archive` in memory, with the bytes of the files `readingDataOf` accepts.
    public func entries(of archive: Data, readingDataOf: (String) -> Bool) throws -> [BackupArchiveEntry] {
        try entries(of: .data(archive)) { readingDataOf($0) ? .data : .skip }
    }

    /// Every entry, with the bytes of every file.
    public func entries(of archive: Data) throws -> [BackupArchiveEntry] {
        try entries(of: .data(archive)) { _ in .data }
    }
}

/// The steps an imported archive goes through, in this order. The first that fails stops the import, and nothing
/// is written anywhere until all four pass (D197a.1, L40–L42).
public enum BackupImportStep: Int, CaseIterable, Sendable, Equatable {
    /// `manifest.json` is one regular file at the snapshot root, read alone.
    case manifestEntry
    /// Its format version is readable and not newer than this app reads.
    case formatVersion
    /// No entry is unsafe: no absolute path, no `..`, no link or special file, no path twice (D195a.2).
    case unsafeEntries
    /// Every listed file is there and matches its size and checksum (D195.2), hashed in chunks.
    case checksums
}

/// Reads an exported archive for 'Restore from File…' and File > Restore from Backup… (D197.3), in the
/// `BackupImportStep` order, writing nothing. A picked file is streamed where it is: the check keeps only the
/// manifest, and attachment bytes are read only by `contents`, after all four steps pass (B1.1).
public struct BackupArchiveImport: Sendable {
    private let archiving: any BackupArchiving
    private let codec: BackupCodec

    public init(archiving: any BackupArchiving, codec: BackupCodec) {
        self.archiving = archiving
        self.codec = codec
    }

    /// Runs the four steps and returns what the manifest says. Keeps no file but the manifest. `onStep` hears each
    /// step as it starts, for the step-order test (L42).
    public func check(
        _ archive: BackupArchiveSource,
        onStep: (BackupImportStep) -> Void = { _ in },
    ) throws -> BackupFolderSummary {
        onStep(.manifestEntry)
        let headers = try archiving.entries(of: archive) { path in
            BackupArchiveSafety.normalized(path) == BackupFormat.manifestPath ? .data : .skip
        }
        let manifest = try BackupArchiveSafety.manifest(in: headers)
        onStep(.formatVersion)
        try codec.checkFormatVersion(ofManifest: manifest)
        onStep(.unsafeEntries)
        try BackupArchiveSafety.check(headers)
        onStep(.checksums)
        var digests: [String: BackupFileDigesting] = [:]
        let streamed = try archiving.entries(of: archive) { path in
            let normalized = BackupArchiveSafety.normalized(path)
            guard normalized != BackupFormat.manifestPath else {
                return .skip
            }
            let digest = BackupFileDigesting(codec.makeDigest())
            digests[normalized] = digest
            return .stream { digest.update($0) }
        }
        // The same entries as the first pass, or the file changed underneath.
        guard streamed.map(\.path) == headers.map(\.path) else {
            throw BackupError.damaged
        }
        return try codec.verify(manifest: manifest, digests: digests.mapValues { $0.finish() })
    }

    /// The checked contents of `archive`, attachments included: `check`, then one more pass that reads every file,
    /// checked again as it's decoded.
    public func contents(
        of archive: BackupArchiveSource,
        onStep: (BackupImportStep) -> Void = { _ in },
    ) throws -> BackupContents {
        _ = try check(archive, onStep: onStep)
        return try codec.decode(BackupArchiveSafety.files(from: archiving.entries(of: archive) { _ in .data }))
    }

    /// A picked file for a restore: `check`, then one more pass that reads the JSON files and unpacks each listed
    /// attachment into `scratch` in chunks, hashing it on the way. Everything this pass read is checked again,
    /// against this pass's own manifest, before it's used. Nothing is unpacked before all four steps pass
    /// (D197a.1), and no attachment is ever held whole: the restore reads them one at a time from `scratch` (B1).
    public func open(
        _ archive: BackupArchiveSource,
        into scratch: any BackupScratchFolder,
        onStep: (BackupImportStep) -> Void = { _ in },
    ) throws -> BackupOpened {
        let listed = try check(archive, onStep: onStep).fileSizes
        var unpacked = BackupUnpacking(scratch: scratch, codec: codec)
        let entries = try archiving.entries(of: archive) { path in
            let normalized = BackupArchiveSafety.normalized(path)
            if normalized == BackupFormat.manifestPath {
                return .data
            }
            guard listed[normalized] != nil else {
                return .skip
            }
            return BackupCodec.isAttachmentPath(normalized) ? unpacked.read(normalized) : .data
        }
        try unpacked.finish()
        try BackupArchiveSafety.check(entries)
        var files = BackupSnapshotFiles()
        var digests = unpacked.digests
        for entry in entries {
            guard case .file(let data?) = entry.kind else {
                continue
            }
            let path = BackupArchiveSafety.normalized(entry.path)
            files[path] = data
            let digest = BackupFileDigesting(codec.makeDigest())
            data.withUnsafeBytes { digest.update($0) }
            digests[path] = digest.finish()
        }
        guard let manifest = files[BackupFormat.manifestPath] else {
            throw BackupError.damaged
        }
        _ = try codec.verify(manifest: manifest, digests: digests)
        return BackupOpened(contents: try codec.decodeDetails(files), attachments: BackupFolderAttachments(scratch))
    }

    /// The checked contents of an archive in memory.
    public func contents(
        of archive: Data,
        onStep: (BackupImportStep) -> Void = { _ in },
    ) throws -> BackupContents {
        try contents(of: .data(archive), onStep: onStep)
    }
}

/// Attachments unpacked into a scratch folder as an archive streams past, each hashed on the way (B1).
struct BackupUnpacking {
    let scratch: any BackupScratchFolder
    let codec: BackupCodec
    private var running: [String: BackupFileDigesting] = [:]
    private var writers: [any BackupFileWriting] = []
    private let failure = BackupFirstError()

    init(scratch: any BackupScratchFolder, codec: BackupCodec) {
        self.scratch = scratch
        self.codec = codec
    }

    /// Streams the file at `path` into a new scratch file. A path seen twice isn't unpacked again; the safety
    /// check refuses the archive afterwards.
    mutating func read(_ path: String) -> BackupArchiveRead {
        guard running[path] == nil else {
            return .skip
        }
        let digest = BackupFileDigesting(codec.makeDigest())
        running[path] = digest
        let writer: any BackupFileWriting
        do {
            writer = try scratch.create(path)
        } catch {
            failure.record(error)
            return .skip
        }
        writers.append(writer)
        let failure = failure
        return .stream { bytes in
            digest.update(bytes)
            failure.attempt { try writer.write(bytes) }
        }
    }

    /// Closes every file, then throws the first write error, if any.
    func finish() throws {
        for writer in writers {
            failure.attempt { try writer.close() }
        }
        try failure.rethrow()
    }

    var digests: [String: BackupFileEntry] {
        running.mapValues { $0.finish() }
    }
}

/// The first error of several steps that can't throw where they run.
final class BackupFirstError {
    private var error: (any Error)?

    func record(_ error: any Error) {
        if self.error == nil {
            self.error = error
        }
    }

    func attempt(_ body: () throws -> Void) {
        guard error == nil else {
            return
        }
        do {
            try body()
        } catch {
            record(error)
        }
    }

    func rethrow() throws {
        if let error {
            throw error
        }
    }
}

/// One file's running size and SHA-256, while its bytes stream past.
final class BackupFileDigesting {
    private let digest: any BackupDigest
    private var byteSize: Int64 = 0

    init(_ digest: any BackupDigest) {
        self.digest = digest
    }

    func update(_ bytes: UnsafeRawBufferPointer) {
        byteSize += Int64(bytes.count)
        digest.update(bytes)
    }

    func finish() -> BackupFileEntry {
        BackupFileEntry(sha256: digest.finish(), byteSize: byteSize)
    }
}

/// The rules for the entries of a picked archive, applied before anything is restored (D195a.2, D197a.1).
public enum BackupArchiveSafety {
    /// The bytes of the one `manifest.json` at the snapshot root (L41). `damaged` when there's none (only one in a
    /// subfolder, or only `/manifest.json` or `../manifest.json`), when there are two, or when it's a link or
    /// anything but a regular file.
    public static func manifest(in entries: [BackupArchiveEntry]) throws -> Data {
        let matches = entries.filter { normalized($0.path) == BackupFormat.manifestPath }
        guard matches.count == 1, case .file(let data?) = matches[0].kind else {
            throw BackupError.damaged
        }
        return data
    }

    /// `damaged` when any entry is unsafe:
    /// - an absolute path, or one with a `..` component, so nothing can land outside the folder
    /// - a symbolic or hard link, or a device or other special file: a backup folder never has one (D195.1). This is
    ///   stricter than D195a.2, which only refuses links that point outside.
    /// - the same path twice
    ///
    /// A leading `./` and directory entries are allowed.
    public static func check(_ entries: [BackupArchiveEntry]) throws {
        var seen = Set<String>()
        for entry in entries {
            let path = normalized(entry.path)
            if case .directory = entry.kind, path.isEmpty {
                continue
            }
            guard BackupFormat.isContained(path) else {
                throw BackupError.damaged
            }
            switch entry.kind {
            case .directory:
                continue
            case .file:
                guard seen.insert(path).inserted else {
                    throw BackupError.damaged
                }
            case .symbolicLink, .hardLink, .other:
                throw BackupError.damaged
            }
        }
    }

    /// The regular files of an archive by relative path, after `check`. A file whose bytes weren't read is
    /// `damaged`.
    public static func files(from entries: [BackupArchiveEntry]) throws -> BackupSnapshotFiles {
        try check(entries)
        var files = BackupSnapshotFiles()
        for entry in entries {
            guard case .file(let data) = entry.kind else {
                continue
            }
            guard let data else {
                throw BackupError.damaged
            }
            files[normalized(entry.path)] = data
        }
        return files
    }

    /// Drops a leading `./` and a trailing `/`. Every other form is checked as it is.
    public static func normalized(_ path: String) -> String {
        var path = path
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        if path == "." {
            return ""
        }
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        return path
    }
}
