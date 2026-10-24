import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Tech Architect's #156 review: Save needs a change (NB8), a failed rename reloads so a retry can succeed
/// (NB3), Merge is off with fewer than two payees left after a failed merge (NB2), and the screen reads the
/// store once per load, never per render (as #155's B1). Names are made up.
@MainActor
@Suite("Payees review fixes")
struct PayeeReviewFixesTests {
    typealias Setup = PayeesViewModelTests.Setup
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private let parcel = Payee(name: "Parcel Point", defaultCategoryID: DefaultCategoryID.shopping)
    private let parcelIn = Payee(name: "PARCELPOINT.IN")
    private let bakery = Payee(name: "Corner Bakery")

    @Test("Save is off until the name changes; outer spaces alone aren't a change, a change of case is (NB8)")
    func saveNeedsChange() throws {
        let setup = try Setup([parcel, bakery])
        let editor = try #require(setup.model.makeEditor(for: bakery.id))
        #expect(!editor.canSave)
        #expect(!editor.save())
        #expect(editor.nameError == nil, "Trying to save an unchanged name isn’t an error")
        editor.name = " Corner Bakery "
        #expect(!editor.canSave)
        editor.name = "corner bakery"
        #expect(editor.canSave)
        editor.name = "Corner Bakery"
        #expect(!editor.canSave)
        #expect(setup.changes == 0, "Nothing was written")
    }

    @Test("A failed rename reloads the list, so trying again can succeed (NB3)")
    func failedRenameRetries() throws {
        let retrying = try Setup(
            [parcel, bakery],
            manage: { repository in FailsOnce(CategoryUseCases(repository: repository).managePayees) },
        )
        let editor = try #require(retrying.model.makeEditor(for: bakery.id))
        // Another window adds a payee while the editor is open; the failed save's reload shows it.
        try retrying.repository.savePayee(Payee(name: "Corner Shop"))
        editor.name = "Corner Cafe"
        #expect(!editor.save())
        #expect(editor.alert?.title == "Couldn’t Save Changes")
        #expect(retrying.model.rows.map(\.name).contains("Corner Shop"), "The failure reloaded the list")
        editor.alert = nil
        #expect(editor.save(), "Try again succeeds")
        #expect(try retrying.payee(bakery.id)?.name == "Corner Cafe")
    }

    @Test("Renaming a payee merged away in another window says so and drops it from the list (NB3)")
    func renameMergedAway() throws {
        let setup = try Setup([parcel, parcelIn])
        let editor = try #require(setup.model.makeEditor(for: parcelIn.id))
        try CategoryUseCases(repository: setup.repository).managePayees.merge([parcelIn.id], into: parcel.id)
        editor.name = "Parcel Point India"
        #expect(!editor.save())
        #expect(editor.alert?.title == "Couldn’t Save Changes")
        #expect(editor.alert?.message == "Your payees weren’t changed. Try again.")
        #expect(setup.model.rows.map(\.name) == ["Parcel Point"])
    }

    @Test("After a failed merge leaves fewer than two payees, Merge is off and no stale name is kept (NB2)")
    func mergeOffAfterFailedReload() throws {
        let setup = try Setup([parcel, parcelIn, bakery], F.spending(2, at: parcel))
        setup.model.selection = [parcel.id, parcelIn.id]
        setup.model.startMerge()
        #expect(setup.model.survivorID == parcel.id)
        // Another window removes the payee whose name would be kept.
        try CategoryUseCases(repository: setup.repository).managePayees.merge([parcel.id], into: bakery.id)
        #expect(!setup.model.merge())
        #expect(setup.model.alert?.title == "Couldn’t Save Changes")
        #expect(setup.model.selection == [parcelIn.id])
        #expect(!setup.model.canMerge)
        #expect(setup.model.survivorID == nil)
    }

    @Test("Typing in Edit Payee and re-rendering the list and Merge Payees read the store no more")
    func noReadsPerRender() throws {
        var counting: CountingPayeeReads?
        let setup = try Setup(
            [parcel, parcelIn, bakery],
            F.spending(2, at: parcel),
            load: { repository in
                let reads = CountingPayeeReads(repository: repository)
                counting = reads
                return reads
            },
        )
        let reads = try #require(counting)
        #expect(reads.count == 1)
        for text in ["P", "Pa", "Par", "parcel", "parcel point"] {
            setup.model.searchText = text
            _ = (setup.model.rows, setup.model.hasPayees, setup.model.selectedText)
        }
        let editor = try #require(setup.model.makeEditor(for: bakery.id))
        for text in ["C", "Co", "Corner", "Corner Cafe", "parcel point"] {
            editor.name = text
            _ = (editor.nameError, editor.canSave, editor.hasUnsavedEdits, editor.title)
        }
        setup.model.selection = [parcel.id, parcelIn.id, bakery.id]
        setup.model.startMerge()
        for id in [parcel.id, parcelIn.id, bakery.id] {
            setup.model.survivorID = id
            _ = (setup.model.mergeRows, setup.model.mergeFootnote, setup.model.canMerge)
        }
        #expect(reads.count == 1, "Only load() reads the store")
    }
}

extension TransactionFeatureFixture {
    fileprivate static func spending(_ count: Int, at payee: Payee) -> [Transaction] {
        (0..<count).map { day in expense(10, on: date(2026, 9, day + 1), payee: payee.id) }
    }
}

/// Fails the first rename with an error that isn't about the name, then forwards to the real use case.
private final class FailsOnce: ManagePayeesUseCase {
    struct Failure: Error {}

    private let real: any ManagePayeesUseCase
    private var failed = false

    init(_ real: any ManagePayeesUseCase) {
        self.real = real
    }

    func rename(_ payeeID: UUID, to name: String) throws {
        if !failed {
            failed = true
            throw Failure()
        }
        try real.rename(payeeID, to: name)
    }

    func merge(_ sourceIDs: [UUID], into survivingID: UUID) throws {
        try real.merge(sourceIDs, into: survivingID)
    }
}

/// Forwards to the real payee listing and counts every read.
@MainActor
private final class CountingPayeeReads: LoadPayeesUseCase {
    private let real: DefaultLoadPayeesUseCase
    var count = 0

    init(repository: any LedgerRepository) {
        real = DefaultLoadPayeesUseCase(repository: repository)
    }

    func listing() throws -> PayeeListing {
        count += 1
        return try real.listing()
    }
}
