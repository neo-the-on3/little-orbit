import Foundation

/// Checking and reading a backup folder one file at a time, so a check never holds a whole backup (Tech Architect
/// B1).
extension BackupCodec {
    /// Checks a backup folder file by file, never holding more than one chunk of a file (B1.2): the manifest as
    /// `decode` does, then every listed file streamed through SHA-256. Returns what the manifest says.
    public func verify(_ folder: some BackupFileReading) throws -> BackupFolderSummary {
        guard let manifest = try folder.data(at: BackupFormat.manifestPath) else {
            throw BackupError.damaged
        }
        var digests: [String: BackupFileEntry] = [:]
        for path in try listedPaths(ofManifest: manifest) where BackupFormat.isContained(path) {
            let digest = BackupFileDigesting(makeDigest())
            if try folder.stream(path, through: { digest.update($0) }) {
                digests[path] = digest.finish()
            }
        }
        return try verify(manifest: manifest, digests: digests)
    }

    /// Checks `manifest` against the size and SHA-256 of each file, worked out elsewhere: every listed file is there
    /// and matches, `shared.json` is listed, and no listed path leaves the folder. Files the manifest doesn't list
    /// are ignored.
    public func verify(manifest data: Data, digests: [String: BackupFileEntry]) throws -> BackupFolderSummary {
        let listed = try listedFiles(ofManifest: data)
        for (path, entry) in listed {
            guard BackupFormat.isContained(path), path != BackupFormat.manifestPath, digests[path] == entry else {
                throw BackupError.damaged
            }
        }
        guard listed[BackupFormat.sharedPath] != nil else {
            throw BackupError.damaged
        }
        return try summary(ofManifest: data)
    }

    /// A stored folder's contents: the manifest first, version first, then only the files it lists, each checked
    /// as it's decoded. Unlisted files are never read.
    public func decode(reading folder: some BackupFileReading) throws -> BackupContents {
        guard let manifest = try folder.data(at: BackupFormat.manifestPath) else {
            throw BackupError.damaged
        }
        var files = BackupSnapshotFiles([BackupFormat.manifestPath: manifest])
        for path in try listedPaths(ofManifest: manifest) where BackupFormat.isContained(path) {
            files[path] = try folder.data(at: path)
        }
        return try decode(files)
    }

    /// A stored folder for a restore: every listed file checked in chunks first (`verify`), then its JSON files
    /// decoded. Attachment bytes are never read here; they're handed to the store one at a time from the folder's
    /// files (B1).
    public func open(_ folder: any BackupFileReading) throws -> BackupOpened {
        _ = try verify(folder)
        guard let manifest = try folder.data(at: BackupFormat.manifestPath) else {
            throw BackupError.damaged
        }
        var files = BackupSnapshotFiles([BackupFormat.manifestPath: manifest])
        for path in try listedPaths(ofManifest: manifest)
        where BackupFormat.isContained(path) && !Self.isAttachmentPath(path) {
            files[path] = try folder.data(at: path)
        }
        return BackupOpened(contents: try decodeDetails(files), attachments: BackupFolderAttachments(folder))
    }

    /// `attachments/<id>`.
    static func isAttachmentPath(_ path: String) -> Bool {
        path.hasPrefix(BackupFormat.attachmentsFolder + "/")
    }
}
