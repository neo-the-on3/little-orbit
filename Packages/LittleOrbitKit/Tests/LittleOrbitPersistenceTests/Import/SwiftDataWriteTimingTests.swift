#if canImport(SwiftData) && os(macOS)
    import Foundation
    import LittleOrbitDomain
    import Testing

    @testable import LittleOrbitPersistence

    /// #235, #256 and #265: the SwiftData store's own write times, on a real store file shaped like Tester2's
    /// on-screen ledger: 10,000 made-up transactions over two accounts, 300 payees, 20 categories and 4 tags,
    /// some tagged, some split, a few with an attachment, reopened as at launch. A single save stays under
    /// 100 ms, a 5,000-row import's commit under 2 s, its Undo Import under 1 s, the Redo of that Undo (the
    /// same rows put back, the same write as the commit) under 2 s, and a Bulk Edit of 3,334 rows, its Undo
    /// and its Redo each under 2 s (`+BulkEdit`, D398). Wall-clock bounds, so the suite runs one test at a time and
    /// prints the timings for the PR. Every bound goes through `TimingScale`: 1 on Tester2's Mac, which gates the
    /// real bounds, and 3 on CI's slower runner (`LITTLE_ORBIT_TIMING_SCALE`, set only in ci.yml).
    ///
    /// Only with `LITTLE_ORBIT_TIMING_LADDER=1`, never in CI, it also times every write path at several sizes
    /// (by default 100, 500, 1,000 and 5,000 rows; `LITTLE_ORBIT_TIMING_SIZES=100,500` picks others), with a
    /// "SwiftData ladder:" line each, a "SwiftData ladder phases:" line with where each write's time went, a
    /// Bulk Edit line per path and one line for the full read after a failed write, for setting
    /// `LedgerWriteTuning` from numbers. The "wholeStore" rows run main's write (5cb0361) for the commit, the
    /// Undo and the Redo, and take minutes. The 5,000-row "oneByOne" row is #265 as Tester2 measured it.
    @Suite("SwiftData write timing (#235)", .serialized)
    @MainActor
    struct SwiftDataWriteTimingTests {
        static let existing = 10_000
        static let rows = 5000
        /// The bound for writing an import's rows: its commit, and its Redo, which is the same write (5,000 new
        /// rows and 200 payees, Tech Architect on #265). Undo Import's 1 s is for removing them.
        static let importWriteBound: Duration = .seconds(2)
        static let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt

        /// One write path for the ladder: how deletes run and whether written transactions link from their parents.
        struct Path: CustomStringConvertible {
            let name: String
            let delete: LedgerDeletePath
            let linksFromParents: Bool
            var description: String { name }
        }

        static let ladderPaths = [
            Path(name: "oneByOne (#265 at 427e3bc)", delete: .oneByOne, linksFromParents: false),
            Path(name: "unlinkFirst", delete: .unlinkFirst, linksFromParents: true),
            Path(name: "unlinkFirst, child-side links", delete: .unlinkFirst, linksFromParents: false),
            Path(name: "wholeStore (main 5cb0361)", delete: .wholeStore, linksFromParents: false),
        ]

        /// The seeded store, made once and copied for each test so every run starts from the same file.
        static let template: Result<URL, any Error> = Result(catching: { try makeTemplate() })

        static func folder() throws -> URL {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("little-orbit-timing-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        static func configuration(in folder: URL) -> StoreConfiguration {
            StoreConfiguration(fileURL: folder.appendingPathComponent("ledger.store"))
        }

        static func ledger() -> LedgerSnapshot {
            let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
            let card = Account(name: "Rewards Card", type: .creditCard, currencyCode: "INR", sortOrder: 2)
            let categories = (0..<20)
                .map { TransactionCategory(name: "Spend \($0)", kind: .expense, sortOrder: Double($0)) }
            let payees = (0..<300).map { Payee(name: "Shop \($0)") }
            let tags = (0..<4).map { Tag(name: "Tag \($0)", sortOrder: Double($0)) }
            var transactions: [Transaction] = []
            var splits: [TransactionSplit] = []
            var attachments: [LedgerAttachment] = []
            transactions.reserveCapacity(existing)
            for index in 0..<existing {
                let transaction = Transaction(
                    type: index.isMultiple(of: 5) ? .income : .expense,
                    amount: Decimal(index % 700 + 2),
                    date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600),
                    timeZoneID: zone.identifier,
                    accountID: index.isMultiple(of: 2) ? savings.id : card.id,
                    categoryID: categories[index % categories.count].id,
                    payeeID: payees[index % payees.count].id,
                    details: "Existing \(index)",
                    tagIDs: index.isMultiple(of: 25) ? [tags[index % tags.count].id] : [],
                )
                transactions.append(transaction)
                if index.isMultiple(of: 200) {
                    splits.append(
                        TransactionSplit(transactionID: transaction.id, categoryID: categories[0].id, amount: 1)
                    )
                    splits.append(
                        TransactionSplit(
                            transactionID: transaction.id,
                            categoryID: categories[1].id,
                            amount: transaction.amount - 1,
                            sortOrder: 1,
                        )
                    )
                }
                if index.isMultiple(of: 500) {
                    attachments.append(
                        LedgerAttachment(
                            transactionID: transaction.id,
                            fileName: "receipt-\(index).txt",
                            contentType: "text/plain",
                            data: Data("made-up receipt \(index)".utf8),
                        )
                    )
                }
            }
            return LedgerSnapshot(
                accounts: [savings, card],
                transactions: transactions,
                categories: categories,
                payees: payees,
                tags: tags,
                splits: splits,
                attachments: attachments,
            )
        }

        static func makeTemplate() throws -> URL {
            let folder = try folder()
            let repository = try LittleOrbitStore.makeRepository(configuration: configuration(in: folder))
            let clock = ContinuousClock()
            let seed = try clock.measure { try repository.replaceLedger(with: ledger()) }
            print("SwiftData timing: seeding \(existing) transactions through the whole-store write: \(seed)")
            return folder
        }

        /// A copy of the seeded store, reopened as at launch, with the first read a launch does.
        static func reopenCopy() throws -> (SwiftDataLedgerRepository, URL) {
            let template = try template.get()
            let folder = try folder()
            for name in try FileManager.default.contentsOfDirectory(atPath: template.path) {
                try FileManager.default.copyItem(
                    at: template.appendingPathComponent(name),
                    to: folder.appendingPathComponent(name),
                )
            }
            let repository = try LittleOrbitStore.makeRepository(configuration: configuration(in: folder))
            let clock = ContinuousClock()
            var count = 0
            let read = try clock.measure { count = try repository.transactions().count }
            #expect(count == existing)
            print("SwiftData timing: first read of \(existing) transactions after reopening: \(read)")
            return (repository, folder)
        }

        struct ImportTiming {
            let commit: Duration
            let undo: Duration
            let redo: Duration
            /// Where each write's time went (`WritePhases`), for the ladder.
            var phases = ""
        }

        /// Commits `count` made-up CSV rows (200 new payees), undoes them and puts them back, timing each.
        static func importAndUndo(
            _ count: Int,
            on repository: SwiftDataLedgerRepository,
        ) throws -> ImportTiming {
            let useCases = ImportUseCases(repository: repository)
            let file = try useCases.pipeline.open(Data(ImportTimingTests.csv(count, year: 2026).utf8))
            let settings = ImportReadSettings(
                mapping: file.suggestedMapping,
                dateOrder: .yearMonthDay,
                decimalSeparator: .period,
                timeZone: zone,
            )
            let preview = useCases.pipeline.preview(
                rows: useCases.pipeline.rows(in: file, settings: settings),
                ledger: try useCases.ledger.ledger(),
                choices: ImportChoices(),
                settings: settings,
                defaultCurrency: "INR",
            )
            #expect(preview.failedCount == 0)
            let clock = ContinuousClock()
            let phases = WritePhases(on: repository)
            defer { phases.stop() }
            var receipt: ImportReceipt?
            let commit = try clock.measure {
                receipt = try useCases.ledger.commit(
                    preview,
                    selection: preview.defaultSelection,
                    fileName: "timing.csv",
                )
            }
            let imported = try #require(receipt)
            #expect(imported.importedCount == count)
            #expect(try repository.transactions().count == existing + count)
            let committed = phases.summary
            phases.begin()
            let undo = try clock.measure { try useCases.ledger.undo(imported) }
            let undone = phases.summary
            #expect(try repository.transactions().count == existing)
            #expect(try repository.payees().count == 300)
            phases.begin()
            let redo = try clock.measure { try repository.redoImport(imported) }
            let redone = phases.summary
            #expect(try repository.transactions().count == existing + count)
            return ImportTiming(
                commit: commit,
                undo: undo,
                redo: redo,
                phases: "commit [\(committed)], undo [\(undone)], redo [\(redone)]",
            )
        }

        @Test("A transaction saved, edited and deleted in a ledger of 10,000")
        func singleSave() throws {
            let (repository, folder) = try Self.reopenCopy()
            defer { try? FileManager.default.removeItem(at: folder) }
            let account = try #require(try repository.accounts().first)
            let payee = try #require(try repository.payees().first)
            let clock = ContinuousClock()
            var lunch = Transaction(
                amount: 250,
                timeZoneID: Self.zone.identifier,
                accountID: account.id,
                payeeID: payee.id,
            )
            let insert = try clock.measure { try repository.saveTransaction(lunch) }
            lunch.details = "Lunch"
            lunch.amount = 275
            let edit = try clock.measure { try repository.saveTransaction(lunch) }
            let delete = try clock.measure { try repository.deleteTransaction(id: lunch.id) }
            print("SwiftData timing: one save into \(Self.existing): insert \(insert), edit \(edit), delete \(delete)")
            // A one-row write stays on the one-by-one path whatever the large-write thresholds become.
            #expect(LedgerWriteTuning.deletePath(forDeleting: 1) == .oneByOne)
            #expect(!LedgerWriteTuning.linksFromParents(forLinking: 1))
            try TimingScale.expect("one save: insert", insert, under: .milliseconds(100))
            try TimingScale.expect("one save: edit", edit, under: .milliseconds(100))
            try TimingScale.expect("one save: delete", delete, under: .milliseconds(100))
            #expect(try repository.transactions().count == Self.existing)
        }

        @Test("5,000 rows imported into a ledger of 10,000, undone and redone")
        func importAndUndo() throws {
            let (repository, folder) = try Self.reopenCopy()
            defer { try? FileManager.default.removeItem(at: folder) }
            let timing = try Self.importAndUndo(Self.rows, on: repository)
            print(
                "SwiftData timing: \(Self.rows) rows into \(Self.existing): "
                    + "commit \(timing.commit), undo \(timing.undo), redo \(timing.redo)"
            )
            try TimingScale.expect("import: commit", timing.commit, under: Self.importWriteBound)
            try TimingScale.expect("import: undo", timing.undo, under: .seconds(1))
            // Redo puts the same rows back as new records, so it shares the commit's bound, not Undo's.
            try TimingScale.expect("import: redo", timing.redo, under: Self.importWriteBound)
        }

        static var ladderSizes: [Int] {
            let sizes = ProcessInfo.processInfo.environment["LITTLE_ORBIT_TIMING_SIZES"]?
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return sizes.flatMap { $0.isEmpty ? nil : $0 } ?? [100, 500, 1000, 5000]
        }

        @Test(
            "Every write path at several sizes (LITTLE_ORBIT_TIMING_LADDER=1)",
            .enabled(if: ProcessInfo.processInfo.environment["LITTLE_ORBIT_TIMING_LADDER"] == "1"),
        )
        func ladder() throws {
            for path in Self.ladderPaths {
                for size in Self.ladderSizes {
                    let (repository, folder) = try Self.reopenCopy()
                    defer { try? FileManager.default.removeItem(at: folder) }
                    repository.deletePathOverride = path.delete
                    repository.linksFromParentsOverride = path.linksFromParents
                    let timing = try Self.importAndUndo(size, on: repository)
                    print(
                        "SwiftData ladder: \(path) rows=\(size) into=\(Self.existing): "
                            + "commit \(timing.commit), undo \(timing.undo), redo \(timing.redo)"
                    )
                    print("SwiftData ladder phases: \(path) rows=\(size): \(timing.phases)")
                }
                try Self.ladderBulkEdit(path)
            }
            try Self.ladderReloadAfterFailedWrite()
        }
    }
#endif
