import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

/// A ledger with two attachments of `size` bytes behind a `StreamingSpySource`, a real folder store behind a
/// `StreamingSpyStorage`, and the recording fake archive.
@MainActor
struct StreamingFixture {
    let source: StreamingSpySource
    let storage: StreamingSpyStorage
    let archiving: RecordingArchiving
    let harness: BackupHarness
    let attachments: [LedgerAttachment]

    init(size: Int) throws {
        let repository = try FeatureFixture.repository()
        guard let account = try repository.ledgerSnapshot().accounts.first else {
            throw BackupError.notFound
        }
        var attachments: [LedgerAttachment] = []
        for index in 0..<2 {
            let spend = Transaction(amount: Decimal(index + 1), accountID: account.id)
            try repository.saveTransaction(spend)
            var bytes = Data(count: size)
            bytes.withUnsafeMutableBytes { raw in
                for offset in stride(from: 0, to: raw.count, by: 997) {
                    raw[offset] = UInt8(truncatingIfNeeded: offset + index)
                }
            }
            let attachment = LedgerAttachment(
                transactionID: spend.id,
                fileName: "Scan \(index).pdf",
                contentType: "application/pdf",
                byteSize: Int64(bytes.count),
                data: bytes,
            )
            try repository.saveAttachment(attachment)
            attachments.append(attachment)
        }
        let source = StreamingSpySource(repository)
        let storage = try StreamingSpyStorage()
        let archiving = RecordingArchiving()
        self.source = source
        self.storage = storage
        self.archiving = archiving
        self.attachments = attachments
        harness = try BackupHarness(
            repository: repository,
            storage: storage,
            archiving: archiving,
            source: { _ in source },
        )
    }

    /// `attachments/<id>`.
    static func path(_ id: UUID) -> String {
        "\(BackupFormat.attachmentsFolder)/\(id.uuidString)"
    }

    /// A backup's folder in the spy store's Backups folder.
    func backupFolder(_ id: UUID) -> URL {
        storage.folder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Whether anything is left in the staging folder.
    var stagingIsEmpty: Bool {
        let staging = URL(fileURLWithPath: storage.folder.path + ".staging")
        return ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty
    }

    /// The backup folders in the Backups folder.
    var folders: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: storage.folder.path)) ?? [])
            .filter { UUID(uuidString: $0) != nil }
    }
}
