import Foundation

/// Writes and reads backup folders (see `BackupFormat`). Pure apart from the injected hashing, so it runs off the
/// main actor. Format 1 is never encrypted (D182).
public struct BackupCodec: Sendable {
    private let hashing: any BackupHashing

    public init(hashing: any BackupHashing) {
        self.hashing = hashing
    }

    /// The folder for `contents`. The same data always gives the same bytes for every file but the manifest, so an
    /// unchanged file can be cloned from the previous backup (D195.1).
    public func encode(_ contents: BackupContents) throws -> BackupSnapshotFiles {
        var entries: [UUID: BackupFileEntry] = [:]
        for attachment in contents.attachments {
            entries[attachment.id] = BackupFileEntry(
                sha256: hashing.sha256Hex(attachment.data),
                byteSize: Int64(attachment.data.count),
            )
        }
        var files = try encode(contents, attachments: entries)
        for attachment in contents.attachments {
            files[Self.attachmentPath(attachment.id)] = attachment.data
        }
        return files
    }

    /// The folder's JSON files and its manifest, listing each attachment with its entry in `attachments`, worked
    /// out while its bytes streamed past (B1). The attachment files themselves aren't included.
    public func encode(
        _ contents: BackupContents,
        attachments: [UUID: BackupFileEntry],
    ) throws -> BackupSnapshotFiles {
        let layout = Layout(contents.ledger)
        var files = BackupSnapshotFiles()
        let shared = SharedFile(
            accounts: layout.accounts,
            categories: layout.categories,
            payees: layout.payees,
            tags: layout.tags,
            sharedSettings: contents.sharedSettings,
            importRules: contents.importRules,
            budgets: contents.budgets,
            scheduledItems: contents.scheduledItems,
            reconciliationHistory: contents.reconciliationHistory,
            unfiled: layout.unfiled,
        )
        files[BackupFormat.sharedPath] = try Self.encoder.encode(shared)
        for (path, year) in layout.years {
            files[path] = try Self.encoder.encode(year)
        }
        var entries = Dictionary(
            uniqueKeysWithValues: files.files.map { path, data in
                (path, BackupFileEntry(sha256: hashing.sha256Hex(data), byteSize: Int64(data.count)))
            }
        )
        for attachment in layout.attachmentBytes {
            entries[Self.attachmentPath(attachment.id)] = attachments[attachment.id] ?? emptyEntry
        }
        let manifest = ManifestFile(
            format: BackupFormat.identifier,
            formatVersion: contents.manifest.formatVersion,
            backup: contents.manifest,
            fingerprint: try fingerprint(
                of: contents.ledger,
                attachments: attachments,
                settings: contents.sharedSettings,
            ),
            files: entries,
        )
        files[BackupFormat.manifestPath] = try Self.encoder.encode(manifest)
        return files
    }

    /// The contents of a backup folder, checked in this order (D197.1): the manifest is there and its format version
    /// can be read (`damaged`) and isn't newer (`newerFormat`), the manifest has no `encryption` section and is a
    /// whole format-1 manifest (`damaged`, D182.3), every path stays inside the folder, and every listed file is there
    /// with its size and checksum (`damaged`, D195.2). Files the manifest doesn't list are ignored. Budgets that break
    /// `LedgerBook.validateStoredBudgets` are `damaged` too (#174 B1).
    public func decode(_ files: BackupSnapshotFiles) throws -> BackupContents {
        try decode(files, manifest: verifiedManifest(files), withBytes: true)
    }

    /// The contents of a folder already checked file by file (`verify`), from its manifest and JSON files only:
    /// each attachment with its details, `data` empty (B1). Its bytes stay in the folder.
    public func decodeDetails(_ files: BackupSnapshotFiles) throws -> BackupContents {
        guard let data = files[BackupFormat.manifestPath] else {
            throw BackupError.damaged
        }
        return try decode(files, manifest: decodedManifest(data), withBytes: false)
    }

    private func decode(
        _ files: BackupSnapshotFiles,
        manifest: ManifestFile,
        withBytes: Bool,
    ) throws -> BackupContents {
        do {
            let shared = try Self.decoder.decode(SharedFile.self, from: files[BackupFormat.sharedPath] ?? Data())
            var ledger = LedgerSnapshot(
                accounts: shared.accounts,
                categories: shared.categories,
                payees: shared.payees,
                tags: shared.tags,
            )
            var records: [AttachmentRecord] = []
            for year in [shared.unfiled] + (try yearFiles(listed: manifest.files, in: files)) {
                ledger.transactions += year.transactions
                ledger.splits += year.splits
                records += year.attachments
            }
            ledger.attachments = try records.map { record in
                let path = Self.attachmentPath(record.id)
                guard manifest.files[path] != nil else {
                    throw BackupError.damaged
                }
                guard withBytes else {
                    return record.attachment(with: Data())
                }
                guard let data = files[path] else {
                    throw BackupError.damaged
                }
                return record.attachment(with: data)
            }
            var contents = BackupContents(
                manifest: manifest.backup,
                ledger: ledger,
                sharedSettings: shared.sharedSettings,
            )
            contents.importRules = shared.importRules
            contents.budgets = shared.budgets
            contents.scheduledItems = shared.scheduledItems
            contents.reconciliationHistory = shared.reconciliationHistory
            contents.scheduledItems = LedgerBook.withoutMissingEditAccounts(in: contents.ledger).scheduledItems
            // The stores' one budget rule: a budget either would refuse is damage, before anything is replaced (B1).
            try LedgerBook.validateStoredBudgets(in: contents.ledger)
            // The stores' one scheduled-item rule: an item either would refuse is damage, before anything is
            // replaced (#26).
            try LedgerBook.validateStoredScheduledItems(in: contents.ledger)
            return contents
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.damaged
        }
    }

    /// What a folder's `manifest.json` says, without checking the other files: enough to list the backup.
    /// Throws `damaged` or `newerFormat` as `decode` does.
    public func summary(ofManifest data: Data) throws -> BackupFolderSummary {
        let manifest = try decodedManifest(data)
        return BackupFolderSummary(
            manifest: manifest.backup,
            fingerprint: manifest.fingerprint,
            byteSize: manifest.files.values.reduce(Int64(data.count)) { $0 + $1.byteSize },
            fileSizes: manifest.files.mapValues(\.byteSize),
        )
    }

    /// A manifest read for the list: a supported one, or what can be read of a newer one without trusting its
    /// shape (D197.2). Throws `damaged` when it isn't a backup manifest or its version can't be read.
    public func reading(manifest data: Data) throws -> BackupManifestReading {
        do {
            return .supported(try summary(ofManifest: data))
        } catch BackupError.newerFormat {
            let hints = try? Self.decoder.decode(NewerManifest.self, from: data)
            return .newer(
                BackupManifestHints(
                    formatVersion: hints?.formatVersion ?? BackupFormat.currentVersion + 1,
                    kind: hints?.backup?.kind.flatMap(BackupKind.init(rawValue:)),
                    createdAt: hints?.backup?.createdAt,
                    nameIndex: hints?.backup?.nameIndex,
                    month: hints?.backup?.month,
                )
            )
        }
    }

    /// The first check on any manifest, before any path, link or checksum check (D197.1, D197a.1, L34): it's a
    /// JSON object with this format's `format` and an integer `formatVersion` (`damaged` otherwise), and that
    /// version isn't newer than this app reads (`newerFormat`). Reads nothing else.
    public func checkFormatVersion(ofManifest data: Data) throws {
        guard let header = try? Self.decoder.decode(VersionHeader.self, from: data),
            header.format == BackupFormat.identifier,
            header.formatVersion >= 1
        else {
            throw BackupError.damaged
        }
        guard header.formatVersion <= BackupFormat.currentVersion else {
            throw BackupError.newerFormat
        }
    }

    /// Identifies the data a ledger holds, ignoring when or how it was backed up (D116.3).
    public func fingerprint(of ledger: LedgerSnapshot, settings: BackupSharedSettings = .init()) throws -> String {
        var entries: [UUID: BackupFileEntry] = [:]
        for attachment in ledger.attachments {
            entries[attachment.id] = BackupFileEntry(
                sha256: hashing.sha256Hex(attachment.data),
                byteSize: Int64(attachment.data.count),
            )
        }
        return try fingerprint(of: ledger.withoutAttachmentBytes, attachments: entries, settings: settings)
    }

    /// The fingerprint of a ledger whose attachments come without bytes, from each one's entry worked out while
    /// its bytes streamed past (B1). The same value `fingerprint(of:)` gives for the ledger with its bytes.
    public func fingerprint(
        of ledger: LedgerSnapshot,
        attachments: [UUID: BackupFileEntry],
        settings: BackupSharedSettings = .init(),
    ) throws -> String {
        var canonical = BackupContents.canonical(ledger)
        // Each attachment counts by its SHA-256, not its bytes in the JSON, so a fingerprint never holds a copy of
        // the attachments (Tech Architect B1).
        let attachmentHashes = canonical.attachments.map { (attachments[$0.id] ?? emptyEntry).sha256 }
        canonical.attachments = canonical.attachments.map { attachment in
            var metadata = attachment
            metadata.data = Data()
            return metadata
        }
        let data = try Self.encoder.encode(
            Fingerprinted(ledger: canonical, attachmentHashes: attachmentHashes, sharedSettings: settings)
        )
        return hashing.sha256Hex(data)
    }

    /// Each attachment's size and SHA-256, its bytes streamed from `bytes` one attachment at a time (B1).
    /// An attachment with no bytes counts as empty.
    public func attachmentEntries(
        of ledger: LedgerSnapshot,
        reading bytes: any BackupAttachmentReading,
    ) throws -> [UUID: BackupFileEntry] {
        var entries: [UUID: BackupFileEntry] = [:]
        for attachment in ledger.attachments {
            let digest = BackupFileDigesting(makeDigest())
            entries[attachment.id] =
                try bytes.stream(attachment.id) { digest.update($0) } ? digest.finish() : emptyEntry
        }
        return entries
    }

    /// The entry of a file with no bytes.
    var emptyEntry: BackupFileEntry {
        BackupFileEntry(sha256: hashing.sha256Hex(Data()), byteSize: 0)
    }

    private func yearFiles(listed: [String: BackupFileEntry], in files: BackupSnapshotFiles) throws -> [YearFile] {
        try listed.keys.sorted().filter(Self.isYearFile)
            .map { path in
                try Self.decoder.decode(YearFile.self, from: files[path] ?? Data())
            }
    }

    private static func isYearFile(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard path.hasSuffix(".json") else {
            return false
        }
        if parts.count == 2 && parts[0] == BackupFormat.transfersFolder {
            return true
        }
        return parts.count == 3 && parts[0] == BackupFormat.accountsFolder
    }

    private func verifiedManifest(_ files: BackupSnapshotFiles) throws -> ManifestFile {
        guard let data = files[BackupFormat.manifestPath] else {
            throw BackupError.damaged
        }
        let manifest = try decodedManifest(data)
        for (path, entry) in manifest.files {
            guard BackupFormat.isContained(path), path != BackupFormat.manifestPath,
                let file = files[path],
                Int64(file.count) == entry.byteSize,
                hashing.sha256Hex(file) == entry.sha256
            else {
                throw BackupError.damaged
            }
        }
        guard manifest.files[BackupFormat.sharedPath] != nil else {
            throw BackupError.damaged
        }
        return manifest
    }

    func makeDigest() -> any BackupDigest {
        hashing.makeDigest()
    }

    /// The files a manifest lists, with their sizes and checksums.
    func listedFiles(ofManifest data: Data) throws -> [String: BackupFileEntry] {
        try decodedManifest(data).files
    }

    func listedPaths(ofManifest data: Data) throws -> [String] {
        try Array(listedFiles(ofManifest: data).keys)
    }

    private func decodedManifest(_ data: Data) throws -> ManifestFile {
        try checkFormatVersion(ofManifest: data)
        // Format 1 has no encryption, so a manifest that claims some is damaged rather than one we can't open.
        guard let header = try? Self.decoder.decode(Header.self, from: data), header.encryption == nil,
            let manifest = try? Self.decoder.decode(ManifestFile.self, from: data),
            manifest.backup.formatVersion == manifest.formatVersion
        else {
            throw BackupError.damaged
        }
        return manifest
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Seconds since 1 Jan 2001 UTC as a JSON number: exact, and independent of the time zone (D133).
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// The two fields every format keeps at the same place (L38).
    private struct VersionHeader: Decodable {
        var format: String
        var formatVersion: Int
    }

    private struct Header: Decodable {
        var encryption: Present?
    }

    /// Matches any JSON value, so `Header` can tell whether an `encryption` key is there without reading it.
    private struct Present: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    private struct ManifestFile: Codable {
        var format: String
        var formatVersion: Int
        var backup: BackupManifest
        /// Identifies the ledger the backup holds (D116.3). A hash, never an amount.
        var fingerprint: String
        /// Every other file in the folder, by relative path.
        var files: [String: BackupFileEntry]
    }

    private struct SharedFile: Codable {
        var accounts: [Account]
        var categories: [TransactionCategory]
        var payees: [Payee]
        var tags: [Tag]
        var sharedSettings: BackupSharedSettings
        var importRules: [BackupReservedRecord]
        var budgets: [Budget]
        var scheduledItems: [ScheduledItem]
        var reconciliationHistory: [BackupReservedRecord]
        /// Transactions with no account, and splits and attachments whose transaction isn't in the backup.
        var unfiled: YearFile
    }

    struct YearFile: Codable {
        var transactions: [Transaction] = []
        var splits: [TransactionSplit] = []
        /// Attachment details; the bytes are in `attachments/<id>`.
        var attachments: [AttachmentRecord] = []
    }

    /// An attachment without its bytes.
    struct AttachmentRecord: Codable {
        var id: UUID
        var transactionID: UUID?
        var fileName: String
        var contentType: String
        var byteSize: Int64
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?

        init(_ attachment: Attachment) {
            id = attachment.id
            transactionID = attachment.transactionID
            fileName = attachment.fileName
            contentType = attachment.contentType
            byteSize = attachment.byteSize
            createdAt = attachment.createdAt
            updatedAt = attachment.updatedAt
            deletedAt = attachment.deletedAt
        }

        func attachment(with data: Data) -> Attachment {
            Attachment(
                id: id,
                transactionID: transactionID,
                fileName: fileName,
                contentType: contentType,
                byteSize: byteSize,
                data: data,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    /// Where each record of a ledger goes, every list sorted by ID.
    private struct Layout {
        var accounts: [Account]
        var categories: [TransactionCategory]
        var payees: [Payee]
        var tags: [Tag]
        var years: [String: YearFile] = [:]
        var unfiled = YearFile()
        var attachmentBytes: [Attachment]

        init(_ ledger: LedgerSnapshot) {
            let ordered = BackupContents.canonical(ledger)
            accounts = ordered.accounts
            categories = ordered.categories
            payees = ordered.payees
            tags = ordered.tags
            attachmentBytes = ordered.attachments
            var pathOfTransaction: [UUID: String] = [:]
            for transaction in ordered.transactions {
                guard let path = Self.path(of: transaction) else {
                    unfiled.transactions.append(transaction)
                    continue
                }
                pathOfTransaction[transaction.id] = path
                years[path, default: YearFile()].transactions.append(transaction)
            }
            for split in ordered.splits {
                if let path = split.transactionID.flatMap({ pathOfTransaction[$0] }) {
                    years[path, default: YearFile()].splits.append(split)
                } else {
                    unfiled.splits.append(split)
                }
            }
            for attachment in ordered.attachments {
                if let path = attachment.transactionID.flatMap({ pathOfTransaction[$0] }) {
                    years[path, default: YearFile()].attachments.append(AttachmentRecord(attachment))
                } else {
                    unfiled.attachments.append(AttachmentRecord(attachment))
                }
            }
        }

        /// `transfers/<year>.json` or `accounts/<id>/<year>.json`, by the year of the transaction's own local date.
        /// `nil` for a transaction with no account.
        static func path(of transaction: Transaction) -> String? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TransactionCalendar.storedTimeZone(transaction.timeZoneID)
            let year = calendar.component(.year, from: transaction.date)
            if transaction.type == .transfer || transaction.transferAccountID != nil {
                return "\(BackupFormat.transfersFolder)/\(year).json"
            }
            guard let account = transaction.accountID else {
                return nil
            }
            return "\(BackupFormat.accountsFolder)/\(account.uuidString)/\(year).json"
        }
    }

    private struct Fingerprinted: Encodable {
        /// With every attachment's bytes left out.
        var ledger: LedgerSnapshot
        /// The SHA-256 of each attachment's bytes, in the ledger's order.
        var attachmentHashes: [String]
        var sharedSettings: BackupSharedSettings
    }
}

/// What a backup folder's manifest says, for the backup list.
public struct BackupFolderSummary: Equatable, Sendable {
    public var manifest: BackupManifest
    public var fingerprint: String
    /// The manifest total, the manifest included: the same as the exported size (S61, D195).
    public var byteSize: Int64
    /// The size of every listed file, by path, for the list's quick check (D196.3).
    public var fileSizes: [String: Int64]
}

/// A manifest as the list reads it (D197.2).
public enum BackupManifestReading: Equatable, Sendable {
    case supported(BackupFolderSummary)
    /// A newer format: only what could be read of it, to list it with its date.
    case newer(BackupManifestHints)
}

/// What a newer-format manifest says in format 1's shape, if anything (D197.2, L35).
public struct BackupManifestHints: Equatable, Sendable {
    public var formatVersion: Int
    public var kind: BackupKind?
    public var createdAt: Date?
    public var nameIndex: Int?
    public var month: String?
}
