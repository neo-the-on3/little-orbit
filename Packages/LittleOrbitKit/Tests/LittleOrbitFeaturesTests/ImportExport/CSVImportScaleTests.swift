import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A 5,200-row file (Tester's Mac pass on #190): the plan runs off the main actor, and Match and Review read rows
/// that were built once, so drawing either step and ticking a row do no per-row formatting. Made-up rows.
@Suite("CSV import at 5,200 rows (#190)", .serialized)
@MainActor
struct CSVImportScaleTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    static let rowCount = 5_200
    static let payeeCount = 1_300

    /// The app's own export format, all in Everyday Savings, with `payeeCount` payees the ledger doesn't have.
    static func bulkFile() -> Data {
        var lines = ["Date,Type,Account,To Account,Amount,Destination Amount,Currency,Category,Payee,Description,Notes"]
        lines.reserveCapacity(rowCount + 1)
        let start = Date(timeIntervalSince1970: 1_767_225_600)  // 1 Jan 2026
        let style = Date.ISO8601FormatStyle(timeZone: F.zone).year().month().day()
        for index in 0..<rowCount {
            let day = start.addingTimeInterval(Double(index % 300) * 86_400).formatted(style)
            let amount = "-\(index % 900 + 1).\(String(format: "%02d", index % 100))"
            lines.append(
                "\(day) 09:00:00,Expense,Everyday Savings,,\(amount),,INR,Food,Bulk Payee \(index % payeeCount),Item \(index),"
            )
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// The fixture accounts plus 500 payees, so each Match row offers a long list.
    static func repository() throws -> InMemoryLedgerRepository {
        let repository = try F.repository()
        for index in 0..<500 {
            try repository.savePayee(Payee(name: "Existing Payee \(index)"))
        }
        return repository
    }

    static func seconds(_ work: () -> Void) -> Double {
        let clock = ContinuousClock()
        let elapsed = clock.measure(work)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test("Columns to Match to Review plans 5,200 rows within a generous bound, and Review shows every row")
    func plansBulkFile() async throws {
        let model = F.model(try Self.repository())
        let clock = ContinuousClock()
        let started = clock.now
        await model.open(data: Self.bulkFile(), fileName: "bulk.csv")
        #expect(model.step == .columns)
        #expect(!model.needsTargetAccount)
        await model.next()
        #expect(model.step == .match)
        #expect(model.payeeMatches.count == Self.payeeCount)
        await model.next()
        #expect(model.step == .review)
        // Generous, for a Debug build on a busy CI machine; a quadratic step would take minutes.
        #expect(clock.now - started < .seconds(60))
        #expect(model.readyCount == Self.rowCount)
        #expect(model.selectedRows.count == Self.rowCount)
        #expect(model.failedRows.isEmpty)
        #expect(model.selectedRows.first?.detail.hasPrefix("Row 2 · ") == true)
    }

    @Test("Reading Match's and Review's rows and counts, as each redraw does, costs no per-row work")
    func readsAreCached() async throws {
        let model = F.model(try Self.repository())
        await model.open(data: Self.bulkFile(), fileName: "bulk.csv")
        await model.next()
        #expect(model.step == .match)
        let match = Self.seconds {
            for _ in 0..<500 {
                _ = model.accountMatches.count + model.categoryMatches.count + model.payeeMatches.count
            }
        }
        #expect(match < 1)
        let options = Set(model.payeeMatches.map(\.options.count))
        #expect(options == [500])
        await model.next()
        #expect(model.step == .review)
        let review = Self.seconds {
            for _ in 0..<500 {
                _ = model.readyCount + model.failedCount + model.shortenedCount + model.alreadyImportedCount
                _ = model.possibleDuplicateCount + model.selectedRows.count + model.unselectedRows.count
                _ = model.importActionTitle(on: .mac)
                _ = model.canImport
            }
        }
        #expect(review < 1)
    }

    @Test("Ticking rows in a 5,200-row Review splits the rows again without formatting them")
    func togglesAreCheap() async throws {
        let model = F.model(try Self.repository())
        await model.open(data: Self.bulkFile(), fileName: "bulk.csv")
        await model.next()
        await model.next()
        let ids = model.selectedRows.prefix(100).map(\.id)
        let elapsed = Self.seconds {
            for id in ids {
                model.toggle(id)
            }
        }
        #expect(elapsed < 5)
        #expect(model.readyCount == Self.rowCount - 100)
        #expect(model.unselectedRows.count == 100)
        #expect(model.unselectedRows.map(\.id) == ids)
    }
}
