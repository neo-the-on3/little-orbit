import Foundation
import LittleOrbitDomain
import Testing

/// D395: Bulk Edit writes only its ticked fields, onto the rows as stored at Apply time. A field another window
/// changed after the sheet opened keeps that value through the apply, its Undo and its Redo. Made-up data:
/// Corner Bakery ₹450.00, changed to ₹999.00 in another window, and StreamBox ₹649.00.
@MainActor
@Suite("Bulk edit on the rows as stored (D395)")
struct BulkEditStoredRowsTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private let bakery = Self.expense(450, "Corner Bakery", on: F.date(2026, 10, 1))
    private let streamBox = Self.expense(649, "StreamBox", on: F.date(2026, 10, 2))
    private let groceries = UUID()

    private static func expense(_ amount: Decimal, _ details: String, on date: Date) -> Transaction {
        var transaction = F.expense(amount, on: date)
        transaction.details = details
        return transaction
    }

    private struct Applied {
        let repository: FakeLedgerRepository
        let useCases: TransactionUseCases
        let change: TransactionChange
    }

    /// A category-only edit of both rows as the sheet read them, after another window set Corner Bakery to ₹999.
    private func applyAfterAnotherWindow() throws -> Applied {
        let repository = try FakeLedgerRepository(
            accounts: F.accounts,
            categories: [TransactionCategory(id: groceries, name: "Groceries", kind: .expense)],
            transactions: [bakery, streamBox],
        )
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        let selection = try repository.transactions()
        var elsewhere = try #require(selection.first { $0.id == bakery.id })
        elsewhere.amount = 999
        try repository.saveTransaction(elsewhere)

        var changes = BulkEditChanges()
        changes.categoryID = .some(groceries)
        let request = BulkEditRequest(
            selection: selection,
            changes: changes,
            payeeName: "",
            accounts: F.accounts,
            timeZoneID: F.india,
            now: F.date(2026, 10, 21),
        )
        return Applied(repository: repository, useCases: useCases, change: try useCases.bulkEdit.apply(request))
    }

    private func stored(_ repository: FakeLedgerRepository, _ id: UUID) throws -> Transaction {
        try #require(try repository.transactions().first { $0.id == id })
    }

    @Test("Apply keeps the amount another window set: only the category is written")
    func applyKeepsOtherFields() throws {
        let repository = try applyAfterAnotherWindow().repository
        #expect(try stored(repository, bakery.id).amount == 999)
        #expect(try stored(repository, bakery.id).categoryID == groceries)
        #expect(try stored(repository, streamBox.id).amount == 649)
        #expect(try stored(repository, streamBox.id).categoryID == groceries)
    }

    @Test("Undo reverts only the category and keeps ₹999; Redo reapplies only the category")
    func undoAndRedoKeepOtherFields() throws {
        let applied = try applyAfterAnotherWindow()
        let (repository, useCases, change) = (applied.repository, applied.useCases, applied.change)
        let outcome = try useCases.changes.outcome(of: change)
        #expect(outcome.touchedFields[bakery.id] == [.category])

        guard
            case .reverted(let inverse, let inverseOutcome) = try useCases.changes.revert(change, expecting: outcome)
        else {
            Issue.record("Undo was refused")
            return
        }
        #expect(try stored(repository, bakery.id).amount == 999)
        #expect(try stored(repository, bakery.id).categoryID == bakery.categoryID)
        #expect(try stored(repository, streamBox.id).categoryID == streamBox.categoryID)

        guard case .reverted = try useCases.changes.revert(inverse, expecting: inverseOutcome) else {
            Issue.record("Redo was refused")
            return
        }
        #expect(try stored(repository, bakery.id).amount == 999)
        #expect(try stored(repository, bakery.id).categoryID == groceries)
        #expect(try stored(repository, streamBox.id).categoryID == groceries)
    }
}
