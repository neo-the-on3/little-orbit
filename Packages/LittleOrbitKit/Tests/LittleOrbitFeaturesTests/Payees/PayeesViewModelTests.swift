import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// iOS Settings › Payees (#24): the list with each payee's last-used category, search, rename, and merging
/// several payees into the one whose name is kept (D287, D291.5), which clears the window's Undo (D287.4).
/// Names are made up.
@MainActor
@Suite("Payees screen")
struct PayeesViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    final class Setup {
        let repository: InMemoryLedgerRepository
        let model: PayeesViewModel
        var removals = 0
        var changes = 0

        init(
            _ payees: [Payee],
            _ transactions: [Transaction] = [],
            load: ((InMemoryLedgerRepository) -> any LoadPayeesUseCase)? = nil,
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
                load: load?(repository) ?? DefaultLoadPayeesUseCase(repository: repository),
                manage: manage?(repository) ?? CategoryUseCases(repository: repository).managePayees,
            )
            var changed: () -> Void = {}
            model = PayeesViewModel(useCases: useCases) { changed() }
            changed = { [unowned self] in changes += 1 }
            model.onRemoval = { [unowned self] in removals += 1 }
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
    private let parcelIn = Payee(
        name: "PARCELPOINT.IN",
        defaultCategoryID: DefaultCategoryID.travel,
        lastUsedAt: F.date(2026, 10, 5),
    )
    private let bakery = Payee(name: "Corner Bakery")

    private func spending(_ count: Int, at payee: Payee) -> [Transaction] {
        (0..<count).map { day in F.expense(10, on: F.date(2026, 9, day + 1), payee: payee.id) }
    }

    private func setup() throws -> Setup {
        try Setup([parcel, parcelIn, bakery], spending(4, at: parcel) + spending(2, at: parcelIn))
    }

    @Test("Each payee shows its last-used category and how many transactions use it, by name")
    func list() throws {
        let setup = try setup()
        #expect(setup.model.rows.map(\.name) == ["Corner Bakery", "Parcel Point", "PARCELPOINT.IN"])
        #expect(setup.model.rows.map(\.detail) == ["0 transactions", "Shopping · 4", "Travel · 2"])
        #expect(
            setup.model.rows.map(\.spokenDetail) == [
                "0 transactions", "Shopping, 4 transactions", "Travel, 2 transactions",
            ]
        )
        #expect(setup.model.hasPayees)
    }

    @Test("Search keeps the payees whose name contains the text, ignoring case")
    func search() throws {
        let setup = try setup()
        setup.model.searchText = " parcel "
        #expect(setup.model.rows.map(\.name) == ["Parcel Point", "PARCELPOINT.IN"])
        setup.model.searchText = "orbit"
        #expect(setup.model.rows.isEmpty)
        #expect(setup.model.hasPayees)
    }

    @Test("Rename saves a trimmed, unique name and keeps Undo")
    func rename() throws {
        let setup = try setup()
        let editor = try #require(setup.model.makeEditor(for: bakery.id))
        #expect(editor.title == "Edit Payee")
        #expect(!editor.hasUnsavedEdits)
        editor.name = " Corner Cafe "
        #expect(editor.hasUnsavedEdits)
        #expect(editor.save())
        #expect(try setup.payee(bakery.id)?.name == "Corner Cafe")
        #expect(setup.model.rows.first?.name == "Corner Cafe")
        #expect(setup.removals == 0, "A rename isn’t a merge, so Undo stays")
        #expect(setup.changes == 1)
    }

    @Test("A name error shows under the field once it's edited, and Save is off while it's invalid (D297.7)")
    func renameNameErrors() throws {
        let setup = try setup()
        let editor = try #require(setup.model.makeEditor(for: bakery.id))
        #expect(editor.nameError == nil)
        editor.name = "   "
        #expect(editor.nameError == "Enter a name.")
        #expect(!editor.canSave)
        #expect(!editor.save())
        editor.name = String(repeating: "a", count: 101)
        #expect(editor.nameError == "Use 100 characters or fewer.")
        #expect(!editor.canSave)
        editor.name = " parcel point "
        #expect(editor.nameError == "There’s already a payee named “Parcel Point”.", "It quotes the stored name")
        #expect(!editor.canSave)
        #expect(!editor.save())
        #expect(editor.alert == nil, "A name error isn’t an alert")
        editor.name = "CORNER BAKERY"
        #expect(editor.nameError == nil, "The payee’s own name isn’t a clash")
        #expect(editor.canSave)
        #expect(try setup.payee(bakery.id)?.name == "Corner Bakery")
        #expect(setup.changes == 0)
    }

    @Test("A rename that fails shows “Couldn’t Save Changes” and nothing changes")
    func renameFails() throws {
        let setup = try Setup([parcel, bakery], manage: { _ in FailingPayees() })
        let editor = try #require(setup.model.makeEditor(for: bakery.id))
        editor.name = "Corner Cafe"
        #expect(!editor.save())
        #expect(editor.alert?.title == "Couldn’t Save Changes")
        #expect(editor.alert?.message == "Your payees weren’t changed. Try again.")
        #expect(editor.nameError == nil)
        #expect(try setup.payee(bakery.id)?.name == "Corner Bakery")
    }

    @Test("A list that can't be read shows “Couldn’t Load Payees”")
    func loadFails() throws {
        let setup = try Setup([parcel], load: { _ in FailingLoad() })
        #expect(setup.model.alert?.title == "Couldn’t Load Payees")
        #expect(setup.model.alert?.message == "Try again.")
        #expect(!setup.model.hasPayees)
    }

    @Test("The removal sentence names one, two or three payees in the system list format (D297.3)")
    func removedSentence() throws {
        let shop = Payee(name: "Corner Shop")
        let setup = try Setup([parcel, parcelIn, bakery, shop], spending(4, at: parcel))
        let removed = { (ids: Set<UUID>) -> String in
            setup.model.selection = ids.union([parcel.id])
            setup.model.startMerge()
            #expect(setup.model.survivorID == parcel.id)
            return setup.model.mergeFootnote
        }
        #expect(removed([bakery.id]).contains(" Corner Bakery is removed from lists, autocomplete and reports. "))
        #expect(
            removed([bakery.id, shop.id])
                .contains(" Corner Bakery and Corner Shop are removed from lists, autocomplete and reports. ")
        )
        #expect(
            removed([bakery.id, shop.id, parcelIn.id])
                .contains(
                    " Corner Bakery, Corner Shop, and PARCELPOINT.IN are removed from lists, autocomplete and reports. "
                )
        )
    }

    @Test("The footnote leaves out the last-used sentence when no payee has a category (D297.4)")
    func footnoteWithoutCategory() throws {
        let shop = Payee(name: "Corner Shop")
        let setup = try Setup([bakery, shop], spending(1, at: shop))
        setup.model.selection = [bakery.id, shop.id]
        setup.model.startMerge()
        #expect(setup.model.survivorID == shop.id)
        #expect(
            setup.model.mergeFootnote
                == "1 transaction will use Corner Shop. Corner Bakery is removed from lists, autocomplete and reports. Merging can’t be undone."
        )
    }

    @Test("Merge needs two payees, keeps the most-used name and says what happens (D287.3, D291.5)")
    func mergeSheet() throws {
        let setup = try setup()
        setup.model.selection = [parcel.id]
        #expect(setup.model.selectedText == "1 selected")
        #expect(!setup.model.canMerge)
        setup.model.selection = [parcel.id, parcelIn.id]
        #expect(setup.model.selectedText == "2 selected")
        #expect(setup.model.canMerge)
        setup.model.startMerge()
        #expect(setup.model.survivorID == parcel.id)
        #expect(setup.model.mergeRows.map(\.transactions) == ["4 transactions", "2 transactions"])
        #expect(
            setup.model.mergeFootnote
                == "6 transactions will use Parcel Point. PARCELPOINT.IN is removed from lists, autocomplete and reports. Parcel Point keeps the most recent last-used category (Travel). Merging can’t be undone."
        )
        setup.model.selection.insert(bakery.id)
        setup.model.survivorID = bakery.id
        #expect(
            setup.model.mergeFootnote
                == "6 transactions will use Corner Bakery. Parcel Point and PARCELPOINT.IN are removed from lists, autocomplete and reports. Corner Bakery keeps the most recent last-used category (Travel). Merging can’t be undone."
        )
    }

    @Test("Merging moves every transaction to the survivor, removes the others and clears Undo (D287.4)")
    func merge() throws {
        let setup = try setup()
        let useCases = TransactionUseCases(repository: setup.repository, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases)
        let lunch = try #require(try setup.repository.transactions().first)
        window.history.record(try useCases.changes.remove(ids: [lunch.id]))
        #expect(window.history.canUndo)
        setup.model.onRemoval = { window.history.clearAfterRemoval() }

        setup.model.selection = [parcel.id, parcelIn.id]
        setup.model.startMerge()
        #expect(setup.model.merge())
        #expect(
            try setup.repository.payees().map(\.id).sorted { $0.uuidString < $1.uuidString }
                == [parcel.id, bakery.id].sorted { $0.uuidString < $1.uuidString }
        )
        #expect(try setup.repository.transactions().filter { $0.payeeID == parcel.id }.count == 5)
        #expect(try setup.payee(parcel.id)?.defaultCategoryID == DefaultCategoryID.travel)
        #expect(setup.model.rows.map(\.name) == ["Corner Bakery", "Parcel Point"])
        #expect(setup.model.selection.isEmpty)
        #expect(!window.history.canUndo)
        #expect(!window.history.canRedo)
        #expect(setup.changes == 1)
    }

    @Test("A merge that fails shows “Couldn’t Save Changes” and changes nothing")
    func mergeFails() throws {
        let setup = try setup()
        setup.model.selection = [parcel.id, parcelIn.id]
        setup.model.startMerge()
        try setup.repository.deletePayee(id: parcelIn.id)
        #expect(!setup.model.merge())
        #expect(setup.model.alert?.title == "Couldn’t Save Changes")
        #expect(setup.model.alert?.message == "Your payees weren’t changed. Try again.")
        #expect(setup.removals == 0)
        #expect(try setup.payee(parcel.id)?.defaultCategoryID == DefaultCategoryID.shopping)
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

/// Fails to read the payee list.
private struct FailingLoad: LoadPayeesUseCase {
    struct Failure: Error {}

    func listing() throws -> PayeeListing {
        throw Failure()
    }
}
