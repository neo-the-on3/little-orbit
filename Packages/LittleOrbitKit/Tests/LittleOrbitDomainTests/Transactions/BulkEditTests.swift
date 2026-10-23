import Foundation
import LittleOrbitDomain
import Testing

@Suite("Bulk edit (D111, D114)")
struct BulkEditTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private var mixed: [Transaction] {
        [
            F.expense(100, on: F.date(2026, 10, 1)),
            F.expense(200, on: F.date(2026, 10, 2)),
            F.expense(300, on: F.date(2026, 10, 3)),
            F.income(500, on: F.date(2026, 10, 4)),
            F.transfer(50, on: F.date(2026, 10, 5)),
        ]
    }

    @Test("Category is available only when every row is the same kind (S40, S74)")
    func categoryAvailability() {
        #expect(BulkEditRules.categoryAvailability(for: mixed) == .mixedTypes)
        #expect(BulkEditRules.categoryAvailability(for: Array(mixed.prefix(3))) == .available(.expense))
        #expect(BulkEditRules.categoryAvailability(for: Array(mixed.prefix(4))) == .mixedTypes)
        #expect(BulkEditRules.categoryAvailability(for: [mixed[4]]) == .transfersOnly)
    }

    @Test("Payee and date: payee skips transfers, date applies to all, category untouched (S73, S77)")
    func payeeSkipsTransfers() throws {
        let bakery = UUID()
        let newDate = F.date(2026, 10, 15)
        var changes = BulkEditChanges()
        changes.payeeID = .some(bakery)
        changes.date = newDate
        let result = try BulkEditRules.apply(changes, to: mixed, accounts: F.accounts, timeZoneID: F.india)
        #expect(result.filter { $0.type != .transfer }.allSatisfy { $0.payeeID == bakery })
        #expect(result.first { $0.type == .transfer }?.payeeID == nil)
        #expect(result.allSatisfy { $0.date == newDate })
        #expect(zip(result, mixed).allSatisfy { $0.categoryID == $1.categoryID && $0.amount == $1.amount })
        #expect(BulkEditRules.includesTransfers(mixed))
        #expect(!BulkEditRules.includesTransfers(Array(mixed.prefix(3))))
    }

    @Test("Untouched fields aren't checked: a 120-character description survives a category edit (S68)")
    func untouchedDescription() throws {
        var rows = Array(mixed.prefix(3))
        rows[0].details = String(repeating: "d", count: 120)
        var changes = BulkEditChanges()
        changes.categoryID = .some(DefaultCategoryID.groceries)
        let result = try BulkEditRules.apply(changes, to: rows, accounts: F.accounts, timeZoneID: F.india)
        #expect(result[0].details?.count == 120)
        #expect(result.allSatisfy { $0.categoryID == DefaultCategoryID.groceries })
        #expect(BulkEditRules.issues(changes).isEmpty)
    }

    @Test("A changed description must fit 100; it applies to all rows (S63, S72)")
    func description() throws {
        var changes = BulkEditChanges()
        changes.details = .some(String(repeating: "x", count: 101))
        #expect(BulkEditRules.issues(changes) == [.descriptionTooLong])
        changes.details = .some("Weekly order")
        let result = try BulkEditRules.apply(changes, to: mixed, accounts: F.accounts, timeZoneID: F.india)
        #expect(result.allSatisfy { $0.details == "Weekly order" })
    }

    @Test("Category isn't applied when the selection mixes kinds, even if set")
    func categoryIgnoredWhenMixed() throws {
        var changes = BulkEditChanges()
        changes.categoryID = .some(DefaultCategoryID.food)
        let result = try BulkEditRules.apply(changes, to: mixed, accounts: F.accounts, timeZoneID: F.india)
        #expect(zip(result, mixed).allSatisfy { $0.categoryID == $1.categoryID })
    }
}
