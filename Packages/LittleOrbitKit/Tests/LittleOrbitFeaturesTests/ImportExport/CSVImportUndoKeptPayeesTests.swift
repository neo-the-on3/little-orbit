import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D384.3 (#254): the Undo Import confirmation counts only the payees it removes, and says how many it keeps
/// because they were changed since the import. Made-up data: the app's own export fixture creates 3 payees.
@Suite("Undo Import keeps changed payees (D384)")
@MainActor
struct CSVImportUndoKeptPayeesTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    private struct Imported {
        let repository: InMemoryLedgerRepository
        let model: CSVImportViewModel
        let created: [Payee]
    }

    private func imported() async throws -> Imported {
        let repository = try F.repository()
        let model = F.model(repository)
        await model.open(data: try F.data("Little Orbit Export"), fileName: "Little Orbit Export.csv")
        await model.next()
        await model.next()
        await model.commit()
        let created = try #require(model.receipt?.createdPayees)
        #expect(created.count == 3)
        return Imported(repository: repository, model: model, created: created)
    }

    private func message(payees: String, kept: String?) -> String {
        let list = ["the new account “Travel Card”", "5 new categories", payees]
            .formatted(.list(type: .and).locale(F.india))
        let keptSentence = kept.map { " \($0)" } ?? ""
        return
            "Everything this import added from “Little Orbit Export.csv” is removed. That includes \(list).\(keptSentence) Nothing else changes."
    }

    @Test("Check 8: one payee renamed since: 2 new payees removed, 1 kept, and Undo Import keeps it")
    func oneKept() async throws {
        let result = try await imported()
        let (repository, model, created) = (result.repository, result.model, result.created)
        var renamed = try #require(try repository.payees().first { $0.id == created[0].id })
        renamed.name += " & Café"
        try repository.savePayee(renamed)
        model.requestUndo()
        #expect(model.isConfirmingUndo)
        #expect(
            model.undoMessage
                == message(payees: "2 new payees", kept: "1 payee you’ve changed since the import is kept.")
        )

        let kept = try #require(try repository.payees().first { $0.id == renamed.id })
        model.undo()
        #expect(model.isUndone)
        #expect(try repository.transactions().isEmpty)
        let after = try #require(try repository.payees().first)
        #expect(try repository.payees().count == 1)
        #expect(after.id == kept.id && after.name == "\(created[0].name) & Café" && !after.isArchived)
        // Its default category came from the import's rows and was one the import created, so it goes with
        // Undo Import's category cleanup, which clears the default; the payee itself stays.
        let createdCategories = Set(try #require(model.receipt?.createdCategories).map(\.id))
        #expect(kept.defaultCategoryID.map(createdCategories.contains) == true)
        #expect(after.defaultCategoryID == nil)
    }

    @Test("Two payees changed since, one renamed and one archived: 1 new payee removed, 2 kept")
    func twoKept() async throws {
        let result = try await imported()
        let (repository, model, created) = (result.repository, result.model, result.created)
        var renamed = try #require(try repository.payees().first { $0.id == created[0].id })
        renamed.name += " & Café"
        try repository.savePayee(renamed)
        var archived = try #require(try repository.payees().first { $0.id == created[1].id })
        archived.isArchived = true
        try repository.savePayee(archived)
        #expect(
            model.undoMessage
                == message(payees: "1 new payee", kept: "2 payees you’ve changed since the import are kept.")
        )
        model.undo()
        #expect(Set(try repository.payees().map(\.id)) == [created[0].id, created[1].id])
    }

    @Test("Nothing changed since: the message is as before, with no kept sentence")
    func noneKept() async throws {
        let result = try await imported()
        let (repository, model) = (result.repository, result.model)
        #expect(model.undoMessage == message(payees: "3 new payees", kept: nil))
        model.undo()
        #expect(try repository.payees().isEmpty)
    }
}
