import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Mac Metadata manager's Payees table (#24 part 5): Name, Last category and Used, the status bar, Merge N
/// Payees with Keep name: (D304), and renaming in the row. Names are made up.
@MainActor
@Suite("Mac Metadata manager: Payees")
struct MetadataPayeesViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    final class Setup {
        let repository: InMemoryLedgerRepository
        let model: MetadataPayeesViewModel
        var removals = 0
        var changes = 0

        init(
            _ payees: [Payee],
            _ transactions: [Transaction] = [],
            manage: ((InMemoryLedgerRepository) -> any ManagePayeesUseCase)? = nil,
        ) throws {
            repository = try F.repository()
            for payee in payees {
                try repository.savePayee(payee)
            }
            for transaction in transactions {
                try repository.saveTransaction(transaction)
            }
            // Saving a transaction marks its payee as used now; put back each payee's own last-used date.
            for payee in payees {
                try repository.savePayee(payee)
            }
            let useCases = PayeeScreenUseCases(
                load: DefaultLoadPayeesUseCase(repository: repository),
                manage: manage?(repository) ?? CategoryUseCases(repository: repository).managePayees,
            )
            var changed: () -> Void = {}
            model = MetadataPayeesViewModel(screen: PayeesViewModel(useCases: useCases) { changed() })
            changed = { [unowned self] in changes += 1 }
            model.screen.onRemoval = { [unowned self] in removals += 1 }
            model.load()
        }

        func payee(_ id: UUID) throws -> Payee? {
            try repository.payees().first { $0.id == id }
        }
    }

    private let parcel = Payee(
        name: "Parcel Point",
        defaultCategoryID: DefaultCategoryID.shopping,
        lastUsedAt: F.date(2026, 10, 1),
    )
    private let parcelPay = Payee(
        name: "Parcel Pay",
        defaultCategoryID: DefaultCategoryID.shopping,
        lastUsedAt: F.date(2026, 10, 3),
    )
    private let parcelIn = Payee(
        name: "PARCELPOINT.IN",
        defaultCategoryID: DefaultCategoryID.travel,
        lastUsedAt: F.date(2026, 10, 5),
    )
    private let bakery = Payee(name: "Corner Bakery")
    private static let renameHint =
        "Return saves · Esc cancels · names must be unique"

    private func spending(_ count: Int, at payee: Payee) -> [Transaction] {
        (0..<count).map { day in F.expense(10, on: F.date(2026, 9, day + 1), payee: payee.id) }
    }

    private func setup() throws -> Setup {
        try Setup(
            [parcel, parcelPay, parcelIn, bakery],
            spending(4, at: parcel) + spending(1, at: parcelPay) + spending(2, at: parcelIn),
        )
    }

    // MARK: Table

    @Test("Each payee is a row by name, with its last-used category and how many transactions use it")
    func rows() throws {
        let setup = try setup()
        let rows = setup.model.rows
        #expect(rows.map(\.name) == ["Corner Bakery", "Parcel Pay", "Parcel Point", "PARCELPOINT.IN"])
        #expect(rows.map(\.lastCategory) == ["", "Shopping", "Shopping", "Travel"])
        #expect(rows.map(\.used) == [0, 1, 4, 2])
        #expect(setup.model.hasPayees)
    }

    @Test("A selected payee that's gone leaves the selection, and so does its rename")
    func selectionPruned() throws {
        let setup = try setup()
        setup.model.beginRename(bakery.id)
        setup.model.selection = [parcel.id, bakery.id]
        try setup.repository.deletePayee(id: bakery.id)
        setup.model.load()
        #expect(setup.model.selection == [parcel.id])
        #expect(setup.model.renaming == nil)
    }

    @Test("The status bar counts the selection; Merge needs two or more payees, with a tooltip saying why not")
    func statusAndMerge() throws {
        let setup = try setup()
        #expect(setup.model.statusText.isEmpty)
        #expect(!setup.model.canMerge)
        setup.model.selection = [parcel.id]
        #expect(setup.model.statusText == "1 selected")
        #expect(!setup.model.canMerge)
        #expect(setup.model.mergeHelp == "Select two or more payees to merge.")
        setup.model.selection = [parcel.id, parcelPay.id, parcelIn.id]
        #expect(setup.model.statusText == "3 selected")
        #expect(setup.model.canMerge)
        #expect(setup.model.mergeHelp == nil)
        #expect(setup.model.canMerge([parcel.id, bakery.id]))
        #expect(!setup.model.canMerge([bakery.id]))
    }

    // MARK: Merge (D287, D291.5, D304)

    @Test("Merge 3 Payees names them in the table's order and keeps the most used name by default")
    func mergeSheet() throws {
        let setup = try setup()
        setup.model.selection = [parcelIn.id, parcel.id, parcelPay.id]
        setup.model.startMerge()
        let merge = try #require(setup.model.merge)
        #expect(merge.title == "Merge 3 Payees")
        #expect(merge.message == "Parcel Pay, Parcel Point and PARCELPOINT.IN become one payee.")
        #expect(merge.keepOptions.map(\.name) == ["Parcel Pay", "Parcel Point", "PARCELPOINT.IN"])
        #expect(merge.keptID == parcel.id)
        #expect(merge.footnote.hasPrefix("7 transactions will use Parcel Point."))
        #expect(merge.footnote.hasSuffix("Merging can’t be undone."))
        merge.keptID = parcelIn.id
        #expect(merge.footnote.hasPrefix("7 transactions will use PARCELPOINT.IN."))
    }

    @Test("On a tie the payee used most recently is kept, then the first by name, as on iOS (D305.3)")
    func mergeTie() throws {
        let setup = try Setup(
            [parcel, parcelPay, parcelIn],
            spending(2, at: parcel) + spending(2, at: parcelPay) + spending(2, at: parcelIn),
        )
        // Parcel Point is selected first and comes first in the table, but PARCELPOINT.IN was used last.
        setup.model.selection = [parcel.id]
        setup.model.selection = [parcel.id, parcelIn.id]
        setup.model.startMerge()
        #expect(setup.model.merge?.keptID == parcelIn.id)
        #expect(setup.model.merge?.title == "Merge 2 Payees")
        #expect(setup.model.merge?.message == "Parcel Point and PARCELPOINT.IN become one payee.")

        setup.model.merge = nil
        setup.model.selection = [parcel.id, parcelPay.id]
        setup.model.startMerge()
        #expect(setup.model.merge?.keptID == parcelPay.id)
    }

    @Test("With the same count and no last use, the first by name is kept")
    func mergeTieByName() throws {
        let corner = Payee(name: "Corner Shop")
        let setup = try Setup([bakery, corner])
        setup.model.selection = [corner.id, bakery.id]
        setup.model.startMerge()
        #expect(setup.model.merge?.keptID == bakery.id)
    }

    @Test("Merge moves the transactions to the kept payee, removes the others and closes the sheet")
    func merge() throws {
        let setup = try setup()
        setup.model.selection = [parcel.id, parcelPay.id, parcelIn.id]
        setup.model.startMerge()
        let merge = try #require(setup.model.merge)
        #expect(merge.confirm())
        #expect(setup.model.merge == nil)
        #expect(setup.model.rows.map(\.name) == ["Corner Bakery", "Parcel Point"])
        #expect(setup.model.rows.last?.used == 7)
        #expect(setup.model.selection.isEmpty)
        #expect(setup.removals == 1)
        #expect(try setup.payee(parcelIn.id) == nil)
    }

    @Test("A merge that fails shows Couldn’t Save Changes on the sheet, which stays open, and changes nothing")
    func mergeFails() throws {
        let setup = try Setup(
            [parcel, parcelIn],
            spending(2, at: parcel),
            manage: { _ in FailingPayees() },
        )
        setup.model.selection = [parcel.id, parcelIn.id]
        setup.model.startMerge()
        let merge = try #require(setup.model.merge)
        #expect(!merge.confirm())
        #expect(merge.alert?.title == "Couldn’t Save Changes")
        #expect(setup.model.screen.alert == nil)
        #expect(setup.model.merge === merge)
        #expect(setup.removals == 0)
        #expect(try setup.payee(parcelIn.id) != nil)
    }

    // MARK: Rename in the row

    @Test("Renaming in the row saves on Return; an unchanged name, ignoring outer spaces, just ends it")
    func rename() throws {
        let setup = try setup()
        setup.model.beginRename(bakery.id)
        #expect(setup.model.selection == [bakery.id])
        #expect(setup.model.renameText == "Corner Bakery")
        #expect(setup.model.statusText == MetadataPayeesViewModelTests.renameHint)
        setup.model.renameText = "  Corner Bakery "
        #expect(setup.model.commitRename())
        #expect(setup.model.renaming == nil)
        #expect(setup.changes == 0)

        setup.model.beginRename(bakery.id)
        setup.model.renameText = "Bakery on Main"
        #expect(setup.model.commitRename())
        #expect(setup.model.renaming == nil)
        #expect(try setup.payee(bakery.id)?.name == "Bakery on Main")
        #expect(setup.model.rows.first?.name == "Bakery on Main")
        #expect(setup.removals == 0)
    }

    @Test(
        "Another payee's name, ignoring case, keeps the row editing with the error in the status bar; Esc keeps the old name"
    )
    func renameClash() throws {
        let setup = try setup()
        setup.model.beginRename(bakery.id)
        setup.model.renameText = " parcel point"
        #expect(!setup.model.commitRename())
        #expect(setup.model.renaming != nil)
        #expect(setup.model.statusText == "There’s already a payee named “Parcel Point”.")
        setup.model.cancelRename()
        #expect(setup.model.renaming == nil)
        #expect(try setup.payee(bakery.id)?.name == "Corner Bakery")
    }

    @Test("A change of case to the payee's own name is saved")
    func renameCase() throws {
        let setup = try setup()
        setup.model.beginRename(parcelIn.id)
        setup.model.renameText = "ParcelPoint.in"
        #expect(setup.model.commitRename())
        #expect(try setup.payee(parcelIn.id)?.name == "ParcelPoint.in")
    }

    @Test("A rename that fails for another reason shows Couldn’t Save Changes and ends the rename")
    func renameFails() throws {
        let setup = try Setup([parcel, bakery], manage: { _ in FailingPayees() })
        setup.model.beginRename(bakery.id)
        setup.model.renameText = "Bakery on Main"
        #expect(!setup.model.commitRename())
        #expect(setup.model.renaming == nil)
        #expect(setup.model.screen.alert?.title == "Couldn’t Save Changes")
    }
}

/// Fails every rename and merge with an error that isn't about the name.
private struct FailingPayees: ManagePayeesUseCase {
    struct Failure: Error {}

    func rename(_: UUID, to _: String) throws {
        throw Failure()
    }

    func merge(_: [UUID], into _: UUID) throws {
        throw Failure()
    }
}
