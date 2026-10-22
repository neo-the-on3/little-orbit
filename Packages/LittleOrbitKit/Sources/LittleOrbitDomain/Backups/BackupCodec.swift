import Foundation

/// Writes and reads `.littleorbit-backup` files (see `BackupFormat`). Pure apart from the injected cryptography,
/// so it runs off the main actor.
public struct BackupCodec: Sendable {
    private let cryptography: any BackupCryptography
    private let allowedIterations: ClosedRange<Int>

    /// `allowedIterations` is only widened by tests that derive keys with fewer iterations to run fast.
    public init(
        cryptography: any BackupCryptography,
        allowedIterations: ClosedRange<Int> = BackupEncryption.allowedIterations,
    ) {
        self.cryptography = cryptography
        self.allowedIterations = allowedIterations
    }

    /// The file for `contents`, encrypted when `password` isn't empty.
    public func encode(_ contents: BackupContents, password: String? = nil) throws -> Data {
        let body = try Self.encoder.encode(contents)
        var encryption: BackupEncryption?
        var stored = body
        if let password, !password.isEmpty {
            let parameters = cryptography.makeEncryption()
            let header = try Self.authenticatedHeader(formatVersion: contents.manifest.formatVersion, parameters)
            stored = try cryptography.seal(body, password: password, encryption: parameters, header: header)
            encryption = parameters
        }
        let envelope = Envelope(
            format: BackupFormat.identifier,
            formatVersion: contents.manifest.formatVersion,
            checksum: cryptography.sha256Hex(stored),
            encryption: encryption,
            body: stored,
        )
        return try Self.encoder.encode(envelope)
    }

    /// Whether `data` is an encrypted backup. Throws for files that aren't backups at all.
    public func isEncrypted(_ data: Data) throws -> Bool {
        try verifiedEnvelope(data).encryption != nil
    }

    /// The contents of a backup file, checked in this order: it's a backup (`damaged`), its format isn't newer
    /// (`newerFormat`), its checksum matches (`damaged`), and an encrypted one opens with `password`
    /// (`passwordRequired`, `incorrectPassword`). Older formats are migrated to the current one.
    public func decode(_ data: Data, password: String? = nil) throws -> BackupContents {
        let envelope = try verifiedEnvelope(data)
        var body = envelope.body
        if let encryption = envelope.encryption {
            guard encryption.isSupported(allowedIterations: allowedIterations) else {
                throw BackupError.damaged
            }
            guard let password, !password.isEmpty else {
                throw BackupError.passwordRequired
            }
            let header = try Self.authenticatedHeader(formatVersion: envelope.formatVersion, encryption)
            body = try cryptography.open(body, password: password, encryption: encryption, header: header)
        }
        let migrated = try BackupMigrations.migrate(body, from: envelope.formatVersion)
        do {
            return try Self.decoder.decode(BackupContents.self, from: migrated)
        } catch {
            throw BackupError.damaged
        }
    }

    /// Identifies the data a ledger holds, ignoring when or how it was backed up (D116.3).
    public func fingerprint(of ledger: LedgerSnapshot, settings: BackupSharedSettings = .init()) throws -> String {
        let canonical = BackupContents.canonical(ledger)
        let data = try Self.encoder.encode(Fingerprinted(ledger: canonical, sharedSettings: settings))
        return cryptography.sha256Hex(data)
    }

    private func verifiedEnvelope(_ data: Data) throws -> Envelope {
        guard let header = try? Self.decoder.decode(Header.self, from: data),
            header.format == BackupFormat.identifier,
            header.formatVersion >= 1
        else {
            throw BackupError.damaged
        }
        guard header.formatVersion <= BackupFormat.currentVersion else {
            throw BackupError.newerFormat
        }
        guard let envelope = try? Self.decoder.decode(Envelope.self, from: data),
            cryptography.sha256Hex(envelope.body) == envelope.checksum
        else {
            throw BackupError.damaged
        }
        return envelope
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

    /// The header fields bound to an encrypted body as AES-GCM associated data: `format`, `formatVersion` and
    /// `encryption`, as sorted-key JSON. Changing any of them makes the file fail to open.
    static func authenticatedHeader(formatVersion: Int, _ encryption: BackupEncryption) throws -> Data {
        try encoder.encode(
            AuthenticatedHeader(format: BackupFormat.identifier, formatVersion: formatVersion, encryption: encryption)
        )
    }

    private struct AuthenticatedHeader: Encodable {
        var format: String
        var formatVersion: Int
        var encryption: BackupEncryption
    }

    private struct Header: Decodable {
        var format: String
        var formatVersion: Int
    }

    private struct Envelope: Codable {
        var format: String
        var formatVersion: Int
        var checksum: String
        var encryption: BackupEncryption?
        var body: Data
    }

    private struct Fingerprinted: Encodable {
        var ledger: LedgerSnapshot
        var sharedSettings: BackupSharedSettings
    }
}

extension LedgerSnapshot: Encodable {
    private enum CodingKeys: String, CodingKey {
        case accounts, transactions, categories, payees, tags, splits, attachments
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(categories, forKey: .categories)
        try container.encode(payees, forKey: .payees)
        try container.encode(tags, forKey: .tags)
        try container.encode(splits, forKey: .splits)
        try container.encode(attachments, forKey: .attachments)
    }
}

/// Upgrades older backup bodies to the current format, one version at a time (D63). Format 1 is the first, so
/// there are no steps yet. The format that adds a reserved section adds the step from the version before it.
enum BackupMigrations {
    static let steps: [Int: @Sendable (Data) throws -> Data] = [:]

    static func migrate(_ body: Data, from version: Int) throws -> Data {
        var body = body
        var version = version
        while version < BackupFormat.currentVersion {
            guard let step = steps[version] else {
                throw BackupError.damaged
            }
            body = try step(body)
            version += 1
        }
        return body
    }
}
