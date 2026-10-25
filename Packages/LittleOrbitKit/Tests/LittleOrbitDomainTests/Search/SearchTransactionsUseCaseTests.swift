import Foundation
import LittleOrbitDomain
import Testing

@MainActor
@Suite("Search use case")
struct SearchTransactionsUseCaseTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @Test("Reads the stored tags and payees once; searching the snapshot finds by tag and payee")
    func readsRepository() throws {
        let goa = F.tag("goa")
        let payee = Payee(name: "Copper Cup Cafe")
        var tagged = F.expense(100, on: F.date(2026, 10, 9))
        tagged.tagIDs = [goa.id]
        var paid = F.expense(50, on: F.date(2026, 10, 10))
        paid.payeeID = payee.id
        let repository = try FakeLedgerRepository(accounts: F.accounts)
        try repository.saveTag(goa)
        try repository.savePayee(payee)
        try repository.saveTransaction(tagged)
        try repository.saveTransaction(paid)
        let snapshot = try DefaultSearchTransactionsUseCase(repository: repository).read()
        let today = F.day(2026, 10, 21)
        #expect(snapshot.ledger.accounts.count == F.accounts.count)
        #expect(snapshot.ledger.payees.map(\.name) == ["Copper Cup Cafe"])

        let byTag = snapshot.search(
            .parse("tag:goa"),
            filter: TransactionSearchFilter(),
            today: today,
            defaultCurrency: "INR",
        )
        #expect(byTag.days.flatMap(\.matches).map(\.id) == [tagged.id])

        let byPayee = snapshot.search(
            .parse("copper"),
            filter: TransactionSearchFilter(),
            today: today,
            defaultCurrency: "INR",
        )
        #expect(byPayee.count == 1)
    }

    @Test("A read failure is thrown, not hidden as no results")
    func readFailure() throws {
        let repository = try FakeLedgerRepository(accounts: F.accounts)
        repository.failsReads = true
        let search = DefaultSearchTransactionsUseCase(repository: repository)
        #expect(throws: (any Error).self) {
            try search.read()
        }
    }
}
