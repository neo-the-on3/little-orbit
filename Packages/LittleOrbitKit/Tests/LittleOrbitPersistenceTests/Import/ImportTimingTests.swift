import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

/// #30 S35: a 5,000-row import stays responsive. Commit and Undo Import run on the main actor, so they save
/// and remove the batch in one pass instead of once per row. Made-up rows; the bounds are loose so a slow CI
/// machine still passes, and the timings are printed for the PR.
@Suite("Import commit and Undo timing (#30 S35)")
@MainActor
struct ImportTimingTests {
    static let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
    static let rows = 5000
    static let bound: Duration = .seconds(2)

    /// `count` made-up rows in `year` over 200 payees, with lakh-grouped incomes and quoted notes.
    static func csv(_ count: Int, year: Int) -> String {
        var text = "Date,Amount,Account,Payee,Description,Notes\r\n"
        for index in 0..<count {
            let month = index % 12 + 1
            let day = index % 28 + 1
            let amount = index.isMultiple(of: 7) ? "1,2\(index % 10)0.50" : "-\(index % 900 + 10).25"
            text += "\(year)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day),"
            text += "\"\(amount)\",Everyday Savings,Kiosk \(index % 200),Row \(index),\"Note, \(index)\"\r\n"
        }
        return text
    }

    static func repository(existing: Int) throws -> InMemoryLedgerRepository {
        let repository = InMemoryLedgerRepository()
        let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
        var transactions: [Transaction] = []
        transactions.reserveCapacity(existing)
        for index in 0..<existing {
            transactions.append(
                Transaction(
                    type: index.isMultiple(of: 5) ? .income : .expense,
                    amount: Decimal(index % 700 + 1),
                    date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600),
                    timeZoneID: zone.identifier,
                    accountID: account.id,
                    details: "Existing \(index)",
                )
            )
        }
        try repository.replaceLedger(with: LedgerSnapshot(accounts: [account], transactions: transactions))
        return repository
    }

    static func preview(_ repository: InMemoryLedgerRepository) throws -> (ImportPreview, any ImportLedgerUseCase) {
        let useCases = ImportUseCases(repository: repository)
        let file = try useCases.pipeline.open(Data(csv(rows, year: 2026).utf8))
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
        return (preview, useCases.ledger)
    }

    static func run(existing: Int) throws -> (commit: Duration, undo: Duration) {
        let repository = try repository(existing: existing)
        let (preview, ledger) = try preview(repository)
        #expect(preview.failedCount == 0)
        let clock = ContinuousClock()
        var receipt: ImportReceipt?
        let commit = try clock.measure {
            receipt = try ledger.commit(preview, selection: preview.defaultSelection, fileName: "timing.csv")
        }
        let imported = try #require(receipt)
        #expect(imported.importedCount == rows)
        #expect(try repository.transactions().count == existing + rows)
        let undo = try clock.measure { try ledger.undo(imported) }
        #expect(try repository.transactions().count == existing)
        print("Import timing: \(rows) rows into \(existing) existing: commit \(commit), undo \(undo)")
        return (commit, undo)
    }

    @Test("5,000 rows into an empty ledger")
    func intoEmpty() throws {
        let timing = try Self.run(existing: 0)
        #expect(timing.commit < Self.bound)
        #expect(timing.undo < Self.bound)
    }

    @Test("5,000 rows into a ledger of 10,000")
    func intoTenThousand() throws {
        let timing = try Self.run(existing: 10_000)
        #expect(timing.commit < Self.bound)
        #expect(timing.undo < Self.bound)
    }

    /// Tech Architect NB1 on #190: the preview looks names up in an index made once per plan, so it no longer
    /// grows with rows × existing names. 5,000 rows, each with its own payee, against 10,000 transactions,
    /// 10,000 payees, 600 categories and 40 accounts, all made up. The same rows are planned against an empty
    /// ledger too: with the index, the existing names add little (before it, 123 s against 1.1 s in Debug).
    @Test("Preview of 5,000 rows against 10,000 existing names")
    func previewScalesWithNames() throws {
        let accounts = (0..<40)
            .map { index in
                Account(name: "Wallet \(index)", type: .savings, currencyCode: "INR", sortOrder: Double(index))
            }
        let parents = (0..<300)
            .map { index in
                TransactionCategory(name: "Shop \(index)", kind: .expense, sortOrder: Double(index))
            }
        let children = parents.map { parent in
            TransactionCategory(name: "Corner", kind: .expense, parentID: parent.id)
        }
        let payees = (0..<10_000).map { Payee(name: "Kiosk \($0)") }
        let transactions = (0..<10_000)
            .map { index in
                Transaction(
                    type: .expense,
                    amount: Decimal(index % 700 + 1),
                    date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600),
                    timeZoneID: Self.zone.identifier,
                    accountID: accounts[index % accounts.count].id,
                    payeeID: payees[index].id,
                    details: "Existing \(index)",
                )
            }
        let ledger = TransactionLedger(
            accounts: accounts,
            transactions: transactions,
            categories: parents + children,
            payees: payees,
        )
        var text = "Date,Amount,Account,Category,Payee,Description\r\n"
        for index in 0..<Self.rows {
            let day = index % 28 + 1
            text += "2026-10-\(day < 10 ? "0" : "")\(day),-\(index % 900 + 10).25,Wallet \(index % 40),"
            text += "Shop \(index % 300) › Corner,Kiosk \(index * 4),Row \(index)\r\n"
        }
        let pipeline = DefaultImportPipeline()
        let file = try pipeline.open(Data(text.utf8))
        let settings = ImportReadSettings(
            mapping: file.suggestedMapping,
            dateOrder: .yearMonthDay,
            decimalSeparator: .period,
            timeZone: Self.zone,
        )
        let rows = pipeline.rows(in: file, settings: settings)
        let clock = ContinuousClock()
        let alone = clock.measure {
            _ = pipeline.preview(
                rows: rows,
                ledger: TransactionLedger(),
                choices: ImportChoices(),
                settings: settings,
                defaultCurrency: "INR",
            )
        }
        var preview: ImportPreview?
        let elapsed = clock.measure {
            preview = pipeline.preview(
                rows: rows,
                ledger: ledger,
                choices: ImportChoices(),
                settings: settings,
                defaultCurrency: "INR",
            )
        }
        let planned = try #require(preview)
        print("Import timing: preview of \(Self.rows) rows: \(alone) alone, \(elapsed) against 10,000 names")
        #expect(elapsed < alone * 2 + .milliseconds(500))
        #expect(planned.failedCount == 0)
        #expect(planned.matches.filter { $0.key.kind == .payee && $0.choice != .new }.count == 2500)
        #expect(planned.matches.filter { $0.key.kind == .account && $0.choice != .new }.count == 40)
    }
}
