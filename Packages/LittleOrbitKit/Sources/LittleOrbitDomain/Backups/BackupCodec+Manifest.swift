import Foundation

extension LedgerSnapshot: Encodable {
    private enum CodingKeys: String, CodingKey {
        case accounts, transactions, categories, payees, tags, splits, attachments, budgets, scheduledItems
    }

    /// Budgets and scheduled items are written only when there are some, so a ledger without them keeps the
    /// fingerprint it had before they existed (#25, #26).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(categories, forKey: .categories)
        try container.encode(payees, forKey: .payees)
        try container.encode(tags, forKey: .tags)
        try container.encode(splits, forKey: .splits)
        try container.encode(attachments, forKey: .attachments)
        if !budgets.isEmpty {
            try container.encode(budgets, forKey: .budgets)
        }
        if !scheduledItems.isEmpty {
            try container.encode(scheduledItems, forKey: .scheduledItems)
        }
    }
}

/// What a newer manifest may still say, each field read only if it's there in format 1's shape.
struct NewerManifest: Decodable {
    var formatVersion: Int
    var backup: NewerManifestBackup?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        backup = try? container.decodeIfPresent(NewerManifestBackup.self, forKey: .backup)
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, backup
    }
}

/// A newer manifest's `backup` section, as far as format 1 can read it.
struct NewerManifestBackup: Decodable {
    var kind: String?
    var createdAt: Date?
    var nameIndex: Int?
    var month: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? container.decodeIfPresent(String.self, forKey: .kind)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        nameIndex = try? container.decodeIfPresent(Int.self, forKey: .nameIndex)
        month = try? container.decodeIfPresent(String.self, forKey: .month)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, createdAt, nameIndex, month
    }
}

extension BackupCodec {
    /// Where an attachment's bytes are in a backup folder.
    static func attachmentPath(_ id: UUID) -> String {
        "\(BackupFormat.attachmentsFolder)/\(id.uuidString)"
    }
}
