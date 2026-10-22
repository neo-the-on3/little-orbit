import Foundation

/// One file of an archive being written: its path in the archive and its size, which goes in its header first.
public struct BackupArchiveFile: Equatable, Sendable {
    public var path: String
    public var byteSize: Int64

    public init(path: String, byteSize: Int64) {
        self.path = path
        self.byteSize = byteSize
    }
}

extension BackupArchiving {
    /// The archive built in memory, then written to `url`, for archivers that have nothing better (test fakes).
    /// Each file must be exactly its listed size.
    public func archive(_ files: [BackupArchiveFile], from folder: any BackupFileReading, to url: URL) throws {
        var all = BackupSnapshotFiles()
        for file in files {
            var data = Data()
            guard try folder.stream(file.path, through: { data.append(contentsOf: $0) }),
                Int64(data.count) == file.byteSize
            else {
                throw BackupError.damaged
            }
            all[file.path] = data
        }
        try archive(all).write(to: url, options: .withoutOverwriting)
    }
}

extension BackupCodec {
    /// Writes a stored backup folder as one archive at `url` (D195a.1, B2): the manifest first, then every file it
    /// lists, sorted, each streamed from `folder` and hashed on the way. A file that's missing, or no longer matches
    /// its size and SHA-256, stops the export with `damaged`; the caller removes what was written. Unlisted files are
    /// never read. A newer-format manifest throws `newerFormat`.
    public func archive(_ folder: any BackupFileReading, with archiving: any BackupArchiving, to url: URL) throws {
        guard let manifest = try folder.data(at: BackupFormat.manifestPath) else {
            throw BackupError.damaged
        }
        let listed = try listedFiles(ofManifest: manifest)
        guard listed[BackupFormat.sharedPath] != nil,
            listed.keys.allSatisfy({ BackupFormat.isContained($0) && $0 != BackupFormat.manifestPath })
        else {
            throw BackupError.damaged
        }
        let files =
            [BackupArchiveFile(path: BackupFormat.manifestPath, byteSize: Int64(manifest.count))]
            + listed.keys.sorted().map { BackupArchiveFile(path: $0, byteSize: listed[$0]?.byteSize ?? 0) }
        let checked = BackupCheckedFolder(folder, manifest: manifest, listed: listed, codec: self)
        try archiving.archive(files, from: checked, to: url)
    }
}

/// A stored folder read for an export: the manifest as already read, and each listed file checked against it as
/// it streams through. The check fails at the file's last chunk, before the archive is finished (B2).
struct BackupCheckedFolder: BackupFileReading {
    let base: any BackupFileReading
    let manifest: Data
    let listed: [String: BackupFileEntry]
    let codec: BackupCodec

    init(_ base: any BackupFileReading, manifest: Data, listed: [String: BackupFileEntry], codec: BackupCodec) {
        self.base = base
        self.manifest = manifest
        self.listed = listed
        self.codec = codec
    }

    func data(at path: String) throws -> Data? {
        if path == BackupFormat.manifestPath {
            return manifest
        }
        guard let entry = listed[path], let data = try base.data(at: path) else {
            return nil
        }
        let digest = BackupFileDigesting(codec.makeDigest())
        data.withUnsafeBytes { digest.update($0) }
        guard digest.finish() == entry else {
            throw BackupError.damaged
        }
        return data
    }

    func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        if path == BackupFormat.manifestPath {
            try manifest.withUnsafeBytes(body)
            return true
        }
        guard let entry = listed[path] else {
            return false
        }
        let digest = BackupFileDigesting(codec.makeDigest())
        let found = try base.stream(path) { chunk in
            try Task.checkCancellation()
            digest.update(chunk)
            try body(chunk)
        }
        guard found, digest.finish() == entry else {
            throw BackupError.damaged
        }
        return true
    }
}
