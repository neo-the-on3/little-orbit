import Foundation

/// The backups listed this session, by ID: those whose folder was read for the list since this service was made.
/// A relaunch starts empty, so a folder that can't be read after it was never listed in this session (D214, D210).
final class BackupListedThisSession: @unchecked Sendable {
    private let lock = NSLock()
    private var ids = Set<UUID>()

    func contains(_ id: UUID) -> Bool {
        lock.withLock { ids.contains(id) }
    }

    func insert(_ listed: some Sequence<UUID>) {
        lock.withLock { ids.formUnion(listed) }
    }
}

/// The list itself couldn't be read: the Backups folder or `status.json` (D211.5). Not a backup that can't be read,
/// so lowering Keep says so with D211.6's general message rather than D208.3's (D214.5), the list shows Couldn’t
/// Load Backups, and every action maps it to its own D211 copy.
struct BackupListUnreadable: Error {
    var underlying: any Error
}

extension BackupService {
    /// The row for a backup folder that couldn't be read at all (R3). This is the one place that decides it.
    /// - Listed earlier this session: its row as last read, condition included, never 'Damaged' (D208.2). Restore…
    ///   then can't open it and says so.
    /// - Otherwise, a relaunch included: `unreadable`, with the folder's own date if it can be read and no size,
    ///   kind, version or counts (D214, D214.3). A read or I/O error is never damage.
    nonisolated static func unreadableRecord(
        _ id: UUID,
        known: BackupRecord?,
        listedThisSession: Bool,
        createdAt: Date?,
    ) -> BackupRecord {
        if listedThisSession, let known, known.condition != .unreadable {
            return known
        }
        return BackupRecord(
            id: id,
            kind: nil,
            createdAt: createdAt ?? BackupRecord.unknownDate,
            formatVersion: 0,
            byteSize: nil,
            accountCount: nil,
            transactionCount: nil,
            attachmentCount: nil,
            condition: .unreadable,
        )
    }

    /// `work`, reading `status.json` or the Backups folder's list, with any failure but cancelling reported as
    /// `BackupListUnreadable` (D211.5, D214.5).
    nonisolated static func readingList<Value>(_ work: () throws -> Value) throws -> Value {
        do {
            return try work()
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackupListUnreadable(underlying: error)
        }
    }
}

extension BackupService {
    /// The list, built from the folders (D195.3). Each folder named by a backup ID is listed:
    /// - with a supported manifest whose files are all there at their listed sizes, and no failed check since:
    ///   restorable
    /// - with a newer format's manifest: `newerFormat`, never checksum-checked (D197.2)
    /// - with no manifest, one that doesn't decode, a missing file or one of the wrong size, or a failed check:
    ///   damaged, with the kind and date last known for it (D196.3, L29, L37)
    /// - whose folder can't be read at all: its own row, from `unreadableRecord` (D208.2, D214)
    ///
    /// The cache in the status is rebuilt from the result, leaving out folders that couldn't be read. If the
    /// Backups folder or `status.json` can't be read, `BackupListUnreadable` is thrown and nothing is saved, so the
    /// list shows Couldn’t Load Backups (R3, D211.5). One folder that can't be read never hides the others. A folder
    /// deleted meanwhile just drops out.
    nonisolated static func catalog(
        storage: any BackupStorage,
        codec: BackupCodec,
        listed: BackupListedThisSession,
    ) throws -> BackupCatalog {
        var status = try readingList { try storage.loadStatus() }
        var records: [BackupRecord] = []
        var read: [BackupRecord] = []
        for id in try readingList({ try storage.storedIDs() }) {
            do {
                let record = record(id, listing: try storage.listing(id: id), known: status.known[id], codec: codec)
                records.append(record)
                read.append(record)
            } catch BackupError.notFound {
                continue
            } catch let error where BackupReadFailure.isReadFailure(error) {
                records.append(
                    unreadableRecord(
                        id,
                        known: status.known[id],
                        listedThisSession: listed.contains(id),
                        createdAt: storage.folderCreationDate(id: id),
                    )
                )
            }
        }
        listed.insert(read.map(\.id))
        // A row kept from an earlier read stays cached as it was; an unreadable one is never cached (D214). While a
        // folder can't be read, what was known about folders not seen now is kept too: one of them may be it.
        let kept = records.filter { $0.condition != .unreadable }
        var known = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if kept.count < records.count {
            known.merge(status.known) { current, _ in current }
        }
        if known != status.known {
            status.known = known
            try? storage.saveStatus(status)
        }
        return BackupCatalog(records: records, status: status)
    }

    nonisolated static func record(
        _ id: UUID,
        listing: BackupFolderListing,
        known: BackupRecord?,
        codec: BackupCodec,
    ) -> BackupRecord {
        guard let data = listing.manifest, let reading = try? codec.reading(manifest: data) else {
            var record =
                known
                ?? BackupRecord(
                    id: id,
                    kind: nil,
                    createdAt: listing.createdAt ?? BackupRecord.unknownDate,
                    formatVersion: 0,
                    byteSize: listing.totalSize,
                    accountCount: nil,
                    transactionCount: nil,
                    attachmentCount: nil,
                )
            record.condition = .damaged
            return record
        }
        switch reading {
        case .newer(let hints):
            return BackupRecord(
                id: id,
                kind: hints.kind ?? known?.kind,
                createdAt: hints.createdAt ?? known?.createdAt ?? listing.createdAt ?? BackupRecord.unknownDate,
                nameIndex: hints.nameIndex ?? known?.nameIndex ?? 1,
                formatVersion: hints.formatVersion,
                byteSize: listing.totalSize,
                // A newer format's counts aren't read, so none are shown, not even an earlier read's.
                accountCount: nil,
                transactionCount: nil,
                attachmentCount: nil,
                month: hints.month,
                condition: .newerFormat,
            )
        case .supported(let summary):
            let manifest = summary.manifest
            let filesThere = summary.fileSizes.allSatisfy { path, size in listing.fileSizes[path] == size }
            let failedCheck = known?.condition == .damaged && known?.fingerprint == summary.fingerprint
            return BackupRecord(
                id: id,
                kind: manifest.kind,
                createdAt: manifest.createdAt,
                nameIndex: manifest.nameIndex,
                formatVersion: manifest.formatVersion,
                byteSize: summary.byteSize,
                accountCount: manifest.accountCount,
                transactionCount: manifest.transactionCount,
                attachmentCount: manifest.attachmentCount,
                fingerprint: summary.fingerprint,
                month: manifest.month,
                condition: filesThere && !failedCheck ? .restorable : .damaged,
            )
        }
    }
}
