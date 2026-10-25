import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D327.1: the import preview re-plans when the data changes while the sheet is open, and Import checks again
/// before it saves. "Another window" is a second import or a direct save to the same in-memory store. Made-up
/// rows from the fixture files.
@Suite("CSV import re-plans when data changes (D327)")
@MainActor
struct CSVImportReplanTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    static let notice = "Your data changed, so this preview was updated."
    static let statement = "Bank Statement Debit Credit"

    /// The bank statement on Review, its rows going to `account`.
    static func review(
        _ repository: InMemoryLedgerRepository,
        into account: String = "Everyday Savings",
        overlayPause: @escaping @MainActor () async -> Void = { try? await Task.sleep(for: .milliseconds(32)) },
    ) async throws -> CSVImportViewModel {
        let model = F.model(repository, overlayPause: overlayPause)
        await model.open(data: try F.data(statement), fileName: "statement.csv")
        await model.next()
        model.targetAccountID = try F.account(account, in: repository).id
        await model.next()
        #expect(model.step == .review)
        return model
    }

    /// Another window imports only the statement's row `rowNumber`.
    static func importOnly(_ rowNumber: Int, into repository: InMemoryLedgerRepository) async throws {
        let other = try await review(repository)
        for row in other.selectedRows where row.id != rowNumber {
            other.toggle(row.id)
        }
        #expect(other.readyCount == 1)
        await other.commit()
        #expect(other.step == .summary)
    }

    static func electricity(_ model: CSVImportViewModel) throws -> ImportReviewRow {
        try #require((model.selectedRows + model.unselectedRows).first { $0.title == "ELECTRICITY BILL" })
    }

    @Test("A change re-plans with the same columns, format and account, keeps unchanged ticks and shows the notice")
    func keepsSettingsAndTicks() async throws {
        let repository = try F.repository()
        let model = try await Self.review(repository)
        var heard: [String] = []
        model.announce = { heard.append($0) }
        let fields = model.columnRows.map(\.field)
        let target = model.targetAccountID
        let bill = try Self.electricity(model)
        model.toggle(bill.id)
        #expect(model.readyCount == 4)
        #expect(model.dataChangedNotice == nil)

        try repository.savePayee(Payee(name: "Tea Stall"))
        await model.dataChanged()
        #expect(model.step == .review)
        #expect(model.dataChangedNotice == Self.notice)
        #expect(heard == [Self.notice])
        #expect(model.columnRows.map(\.field) == fields)
        #expect(model.dateOrder == .dayMonthYear)
        #expect(model.decimalSeparator == .period)
        #expect(model.targetAccountID == target)
        // The status didn't change, so the user's untick stays.
        #expect(model.readyCount == 4)
        #expect(model.unselectedRows.map(\.id) == [bill.id])

        // VoiceOver hears the notice once, not again while it stays.
        try repository.savePayee(Payee(name: "Bus Depot"))
        await model.dataChanged()
        #expect(model.dataChangedNotice == Self.notice)
        #expect(heard == [Self.notice])

        // Moving to another step clears it; a signal with no real change shows nothing.
        model.back()
        #expect(model.dataChangedNotice == nil)
        await model.dataChanged()
        #expect(model.dataChangedNotice == nil)
    }

    @Test("A ticked row that is now Already imported is unticked and moves to Not Selected, and can be ticked again")
    func nowAlreadyImported() async throws {
        let repository = try F.repository()
        let model = try await Self.review(repository)
        #expect(model.readyCount == 5)
        try await Self.importOnly(2, into: repository)
        #expect(model.readyCount == 5)

        await model.dataChanged()
        #expect(model.dataChangedNotice == Self.notice)
        #expect(model.alreadyImportedCount == 1)
        #expect(model.readyCount == 4)
        let row = try #require(model.unselectedRows.first)
        #expect(model.unselectedRows.count == 1)
        #expect(row.id == 2)
        #expect(row.message == "Already imported")
        model.toggle(row.id)
        #expect(model.readyCount == 5)
    }

    @Test("A row whose status changed takes D42's default: ticked when ready, unticked when a possible duplicate")
    func changedStatusTakesDefault() async throws {
        let repository = try F.repository()
        let savings = try F.account("Everyday Savings", in: repository)
        let near = Transaction(
            type: .expense,
            amount: 450,
            date: Date(timeIntervalSince1970: 1_791_000_000),
            timeZoneID: "Asia/Kolkata",
            accountID: savings.id,
            details: "UPI-CORNER SHOP",
        )
        try repository.saveTransaction(near)
        let model = try await Self.review(repository)
        #expect(model.possibleDuplicateCount == 1)
        #expect(model.readyCount == 4)

        // The near transaction is deleted elsewhere: the row is ready now, so it starts ticked.
        try repository.deleteTransaction(id: near.id)
        await model.dataChanged()
        #expect(model.possibleDuplicateCount == 0)
        #expect(model.readyCount == 5)

        // A close match for the electricity bill is added: that row starts unticked.
        try repository.saveTransaction(
            Transaction(
                type: .expense,
                amount: F.dec("1234.50"),
                date: Date(timeIntervalSince1970: 1_791_000_000),
                timeZoneID: "Asia/Kolkata",
                accountID: savings.id,
                details: "Electricity bill",
            )
        )
        await model.dataChanged()
        #expect(model.possibleDuplicateCount == 1)
        #expect(model.readyCount == 4)
        #expect(model.unselectedRows.map(\.title) == ["ELECTRICITY BILL"])
        #expect(model.unselectedRows.first?.message == "Possible duplicate")
    }

    @Test("Import checks again: if the data changed, nothing is saved and Review shows the new counts")
    func importRechecks() async throws {
        let repository = try F.repository()
        let changes = F.Changes()
        let model = F.model(repository, changes: changes)
        await model.open(data: try F.data(Self.statement), fileName: "statement.csv")
        await model.next()
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await model.next()
        var heard: [String] = []
        model.announce = { heard.append($0) }
        // The other window's change lands without the signal reaching this sheet first.
        try await Self.importOnly(2, into: repository)

        await model.commit()
        #expect(model.step == .review)
        #expect(model.dataChangedNotice == Self.notice)
        #expect(heard == [Self.notice])
        #expect(changes.count == 0)
        #expect(try repository.transactions().count == 1)
        #expect(model.alreadyImportedCount == 1)
        #expect(model.readyCount == 4)

        await model.commit()
        #expect(model.step == .summary)
        #expect(model.dataChangedNotice == nil)
        #expect(try repository.transactions().count == 5)
        #expect(changes.count == 1)
    }

    @Test("Match choices are kept while their record exists; a removed one goes back to its automatic match")
    func matchChoices() async throws {
        let repository = try F.repository()
        let kiosk = Payee(name: "Kiosk")
        let plaza = Payee(name: "Films Plaza")
        try repository.savePayee(kiosk)
        try repository.savePayee(plaza)
        let model = F.model(repository)
        await model.open(data: try F.data("Little Orbit Export"), fileName: "export.csv")
        await model.next()
        #expect(model.step == .match)
        let shop = try #require(model.payeeMatches.first { $0.name == "Corner Shop" })
        let cinema = try #require(model.payeeMatches.first { $0.name == "Cinema Hall" })
        await model.setChoice(.existing(kiosk.id), for: shop.id)
        await model.setChoice(.existing(plaza.id), for: cinema.id)

        try repository.deletePayee(id: kiosk.id)
        await model.dataChanged()
        #expect(model.step == .match)
        #expect(model.dataChangedNotice == Self.notice)
        #expect(model.payeeMatches.first { $0.name == "Corner Shop" }?.choice == .new)
        #expect(model.payeeMatches.first { $0.name == "Cinema Hall" }?.choice == .existing(plaza.id))
        #expect(model.payeeMatches.first { $0.name == "Corner Shop" }?.options.contains { $0.id == kiosk.id } == false)
    }

    @Test("When the target account is deleted, the Account step asks again, with the notice")
    func targetAccountGone() async throws {
        let repository = try F.repository()
        let wallet = try F.account("Corner Wallet", in: repository)
        let model = try await Self.review(repository, into: "Corner Wallet")
        try repository.deleteAccount(id: wallet.id)
        await model.dataChanged()
        #expect(model.step == .account)
        #expect(model.targetAccountID == nil)
        #expect(model.dataChangedNotice == Self.notice)
        #expect(!model.accountOptions.contains { $0.id == wallet.id })
    }

    @Test("Nothing re-plans before a file is open or after the import is done")
    func onlyWhilePlanning() async throws {
        let repository = try F.repository()
        let empty = F.model(repository)
        try repository.savePayee(Payee(name: "Tea Stall"))
        await empty.dataChanged()
        #expect(empty.dataChangedNotice == nil)

        let model = try await Self.review(repository)
        await model.commit()
        #expect(model.step == .summary)
        try repository.savePayee(Payee(name: "Bus Depot"))
        await model.dataChanged()
        #expect(model.step == .summary)
        #expect(model.dataChangedNotice == nil)
    }

    @Test("If the sheet closes while Importing… shows, nothing is saved")
    func closedDuringImport() async throws {
        let repository = try F.repository()
        let gate = PauseGate()
        let model = try await Self.review(repository, overlayPause: gate.pause)
        let saving = Task { await model.commit() }
        await gate.waitUntilPaused()
        #expect(model.isWorking)
        model.close()
        gate.open()
        await saving.value
        #expect(try repository.transactions().isEmpty)
        #expect(model.step == .review)
        #expect(!model.isWorking)
    }

    @Test("D327.4: the summary counts unticked rows as “Not selected”, right after “Can’t import”")
    func summaryNotSelected() async throws {
        let repository = try F.repository()
        let savings = try F.account("Everyday Savings", in: repository)
        try repository.saveTransaction(
            Transaction(
                type: .expense,
                amount: 450,
                date: Date(timeIntervalSince1970: 1_791_000_000),
                timeZoneID: "Asia/Kolkata",
                accountID: savings.id,
                details: "UPI-CORNER SHOP",
            )
        )
        let model = try await Self.review(repository)
        model.toggle(try Self.electricity(model).id)
        await model.commit()
        #expect(model.notImportedLines.map(\.label) == ["Can’t import", "Not selected", "Possible duplicates"])
        #expect(model.notImportedLines.map(\.count) == [1, 1, 1])
    }
}

/// Holds Import at its overlay pause until the test opens it, so the sheet closes at a known point while
/// “Importing…” shows, not after a wall-clock wait.
@MainActor
final class PauseGate {
    private var isPaused = false
    private var paused: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?

    /// The pause Import awaits: it reports that it's waiting, then waits for `open()`.
    func pause() async {
        isPaused = true
        paused?.resume()
        paused = nil
        await withCheckedContinuation { held = $0 }
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { paused = $0 }
    }

    func open() {
        held?.resume()
        held = nil
    }
}
