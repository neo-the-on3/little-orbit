#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitPersistence
    import Testing

    /// D63: a restore replaces the whole SwiftData ledger. B1: backups read attachments one at a time, in chunks,
    /// and a restore takes each one from a file.
    @MainActor
    @Suite("SwiftData backup source", .timeLimit(.minutes(2)))
    struct SwiftDataBackupSourceTests {
        @Test("Replacing the ledger leaves exactly the backup's records and balances")
        func replace() throws {
            let repository = try LittleOrbitStore.makeRepository(configuration: .inMemory)
            let kept = Account(
                name: "Kept",
                type: .cash,
                currencyCode: "KWD",
                openingBalance: Decimal(string: "1.234") ?? 0,
            )
            try repository.saveAccount(kept)
            try repository.saveTransaction(Transaction(amount: Decimal(string: "0.200") ?? 0, accountID: kept.id))
            let snapshot = try repository.ledgerSnapshot()
            let balance = try repository.balance(of: kept.id, today: ledgerToday)

            let extra = Account(name: "Added later", type: .cash, currencyCode: "INR", openingBalance: 10)
            try repository.saveAccount(extra)
            try repository.saveTransaction(Transaction(amount: 5, accountID: kept.id))

            try repository.replaceLedger(with: snapshot)
            #expect(try repository.accounts().map(\.id) == [kept.id])
            #expect(try repository.balance(of: kept.id, today: ledgerToday) == balance)
            #expect(try repository.transactions().count == 1)
        }
        /// The attachments come back in a `LedgerSnapshot`: Swift Testing's own `Attachment` hides the ledger's here.
        private func withAttachments() throws -> (SwiftDataLedgerRepository, LedgerSnapshot) {
            let repository = try LittleOrbitStore.makeRepository(configuration: .inMemory)
            let account = Account(name: "Wallet", type: .cash, currencyCode: "INR", openingBalance: 1)
            try repository.saveAccount(account)
            var ledger = LedgerSnapshot()
            for index in 0..<2 {
                let spend = Transaction(amount: Decimal(index + 1), accountID: account.id)
                try repository.saveTransaction(spend)
                let data = Data((0..<(BackupChunk.size * 5 / 2)).map { UInt8(truncatingIfNeeded: $0 &+ index) })
                let attachment = Attachment(
                    transactionID: spend.id,
                    fileName: "Scan \(index).pdf",
                    contentType: "application/pdf",
                    byteSize: Int64(data.count),
                    data: data,
                )
                try repository.saveAttachment(attachment)
                ledger.attachments.append(attachment)
            }
            return (repository, ledger)
        }

        @Test("A backup gets the records without attachment bytes, and the bytes in chunks, one attachment at a time")
        func backupReads() async throws {
            let (repository, ledger) = try withAttachments()
            let attachments = ledger.attachments
            let snapshot = try repository.backupSnapshot()
            #expect(snapshot.attachments.map(\.data.count) == [0, 0])
            #expect(Set(snapshot.attachments.map(\.byteSize)) == Set(attachments.map(\.byteSize)))
            let reader = try repository.attachmentBytes()
            let ids = attachments.map(\.id)
            // Off the main actor, the way a backup reads them.
            let read =
                try await Task.detached {
                    try ids.map { id in
                        var bytes = Data()
                        var largest = 0
                        _ = try reader.stream(id) {
                            largest = max(largest, $0.count)
                            bytes.append(contentsOf: $0)
                        }
                        return (bytes, largest)
                    }
                }
                .value
            #expect(read.map(\.0) == attachments.map(\.data))
            #expect(read.allSatisfy { $0.1 <= BackupChunk.size })
            #expect(try reader.stream(UUID()) { _ in Issue.record("No bytes for an unknown ID") } == false)
        }

        @Test("A restore takes each attachment's bytes from a backup folder's file")
        func restoreFromFiles() throws {
            let (repository, ledger) = try withAttachments()
            let attachments = ledger.attachments
            let snapshot = try repository.backupSnapshot()
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftdata-restore-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: folder)
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
            }
            let storage = try FileBackupStorage(folder: folder)
            let id = UUID()
            let ids = Dictionary(uniqueKeysWithValues: attachments.map { ("attachments/\($0.id.uuidString)", $0.id) })
            try storage.write(
                BackupSnapshotFiles(["manifest.json": Data("{}".utf8)]),
                attachments: BackupAttachmentWrites(ids: ids, bytes: try repository.attachmentBytes()),
                id: id,
                cloningFrom: nil,
            )
            try repository.deleteAttachment(id: attachments[0].id)

            try repository.replaceLedger(
                with: snapshot,
                attachments: BackupFolderAttachments(try storage.files(id: id)),
            )
            let restored = try repository.ledgerSnapshot().attachments
            #expect(Set(restored.map(\.data)) == Set(attachments.map(\.data)))
            #expect(Set(restored.map(\.byteSize)) == Set(attachments.map(\.byteSize)))
        }
    }
#endif
