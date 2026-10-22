import Foundation

/// Checking backups in full, and remembering what each check found (D196.3).
extension BackupService {
    /// `check`'s result, with the backup's condition remembered: a damaged backup shows as 'Damaged' from then on
    /// (D196.3). A read error is `unreadableBackup` and remembers nothing, so the backup stays restorable (D208.2).
    nonisolated static func remembering<Value>(
        _ id: UUID,
        storage: any BackupStorage,
        check: () throws -> Value,
    ) throws -> Value {
        do {
            let value = try check()
            remember([id: .restorable], storage: storage)
            return value
        } catch BackupError.damaged {
            remember([id: .damaged], storage: storage)
            throw BackupError.damaged
        } catch let error where BackupReadFailure.isReadFailure(error) {
            // A check that couldn't run marks nothing: the backup stays restorable (D208.2).
            throw BackupError.unreadableBackup
        }
    }

    /// `records` with each one that isn't of a newer format read and checked in full. A folder gone meanwhile drops
    /// out; any other read error is thrown.
    nonisolated static func checkedInFull(
        _ records: [BackupRecord],
        storage: any BackupStorage,
        codec: BackupCodec,
    ) throws -> [BackupRecord] {
        var checked: [BackupRecord] = []
        var conditions: [UUID: BackupCondition] = [:]
        for var record in records {
            if record.condition != .newerFormat {
                do {
                    _ = try codec.verify(storage.files(id: record.id))
                    record.condition = .restorable
                } catch BackupError.damaged {
                    record.condition = .damaged
                } catch BackupError.newerFormat {
                    record.condition = .newerFormat
                } catch BackupError.notFound {
                    continue
                }
                conditions[record.id] = record.condition
            }
            checked.append(record)
        }
        remember(conditions, storage: storage)
        return checked
    }

    /// Updates the cached condition of known backups. Losing this only loses the 'Damaged' mark until the next
    /// check, so a failed save is ignored.
    nonisolated static func remember(_ conditions: [UUID: BackupCondition], storage: any BackupStorage) {
        guard var status = try? storage.loadStatus() else {
            return
        }
        var changed = false
        for (id, condition) in conditions {
            if var record = status.known[id], record.condition != condition {
                record.condition = condition
                status.known[id] = record
                changed = true
            }
        }
        if changed {
            try? storage.saveStatus(status)
        }
    }

    /// Which attachment files a new backup gets, and which of them are unchanged since `earlier`: the same size
    /// and SHA-256 in its manifest, so they're cloned rather than written again (D195.1). The earlier folder's
    /// files are checked when the new folder is read back.
    nonisolated static func attachmentWrites(
        _ ledger: LedgerSnapshot,
        entries: [UUID: BackupFileEntry],
        bytes: any BackupAttachmentReading,
        earlier: UUID?,
        storage: any BackupStorage,
        codec: BackupCodec,
    ) throws -> BackupAttachmentWrites {
        let listed =
            earlier.flatMap { id in
                (try? storage.files(id: id).data(at: BackupFormat.manifestPath))
                    .flatMap { $0 }
                    .flatMap { try? codec.listedFiles(ofManifest: $0) }
            } ?? [:]
        var writes = BackupAttachmentWrites(bytes: bytes)
        for attachment in ledger.attachments {
            let path = BackupCodec.attachmentPath(attachment.id)
            writes.ids[path] = attachment.id
            if let entry = entries[attachment.id], listed[path] == entry {
                writes.unchanged.insert(path)
            }
        }
        return writes
    }

    /// A backup checked again, file by file, for a restore: a stored folder, or a picked file with its attachments
    /// unpacked into a scratch folder the caller removes (B1).
    func openForRestore(_ source: BackupSource) async throws -> (BackupOpened, (any BackupScratchFolder)?) {
        let storage = self.storage
        let codec = self.codec
        let archiving = self.archiving
        return
            try await Task.detached(executorPreference: BackupWorkExecutor.shared, priority: .userInitiated) {
                switch source {
                case .stored(let id):
                    let opened = try Self.remembering(id, storage: storage) {
                        try codec.open(storage.files(id: id))
                    }
                    return (opened, nil)
                case .archive(let archive):
                    let scratch = try storage.makeScratch()
                    do {
                        let opened = try BackupArchiveImport(archiving: archiving, codec: codec)
                            .open(archive, into: scratch)
                        return (opened, scratch)
                    } catch {
                        scratch.remove()
                        throw error
                    }
                }
            }
            .value
    }
}
