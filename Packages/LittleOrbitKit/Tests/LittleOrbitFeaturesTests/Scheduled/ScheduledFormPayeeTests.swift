import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Scheduled form's payee field (#197): the #23 autocomplete, with a "Create “‹text›”" row, subtitled "New
/// payee", that alone creates a payee.
@MainActor
@Suite("Scheduled form payee field (#197)")
struct ScheduledFormPayeeTests {
    private func form(_ scene: ScheduledScene) throws -> ScheduledFormViewModel {
        let list = scene.feature().makeList()
        list.load()
        list.openNew()
        return try #require(list.form)
    }

    private func payees(_ scene: ScheduledScene) throws -> [Payee] {
        try scene.repository.payees().filter { $0.deletedAt == nil }
    }

    @Test("Typing suggests matching payees, then Create “‹text›” with New payee")
    func suggestions() throws {
        let scene = try ScheduledScene()
        try scene.repository.savePayee(Payee(name: "Gold's Gym", createdAt: scene.now))
        let form = try form(scene)
        form.payeeText = "gym"
        #expect(form.payeeSuggestions.map(\.text) == ["Gold's Gym"])
        #expect(form.createPayeeTitle == "Create “gym”")
        #expect(form.createPayeeSubtitle == "New payee")
        #expect(form.payeeID == nil)
    }

    @Test("Picking a suggestion picks the payee and fills an empty category with its last one")
    func pickSuggestion() throws {
        let scene = try ScheduledScene()
        let gym = Payee(name: "Gold's Gym", defaultCategoryID: scene.housing.id, createdAt: scene.now)
        try scene.repository.savePayee(gym)
        let form = try form(scene)
        form.payeeText = "gold"
        form.choosePayee(try #require(form.payeeSuggestions.first))
        #expect(form.payeeID == gym.id)
        #expect(form.payeeText == "Gold's Gym")
        #expect(form.categoryID == scene.housing.id)
        #expect(form.payeeSuggestions.isEmpty)
        #expect(form.createPayeeTitle == nil)
    }

    @Test("Typing an existing payee's name in another case picks it, with no Create row")
    func exactName() throws {
        let scene = try ScheduledScene()
        let gym = Payee(name: "Gold's Gym", createdAt: scene.now)
        try scene.repository.savePayee(gym)
        let form = try form(scene)
        form.payeeText = "  gold's gym "
        #expect(form.payeeID == gym.id)
        #expect(form.createPayeeTitle == nil)
    }

    @Test("Only the Create row creates a payee; saving with unmatched text creates none")
    func createOnlyFromRow() throws {
        let scene = try ScheduledScene()
        var form = try form(scene)
        form.amountText = "1200"
        form.payeeText = "Gym Co"
        #expect(form.save())
        #expect(try payees(scene).isEmpty)
        #expect(try scene.repository.scheduleLedger().scheduledItems.first?.payeeID == nil)

        form = try self.form(scene)
        form.amountText = "1200"
        form.payeeText = " Gym Co "
        form.createPayee()
        let created = try #require(try payees(scene).first)
        #expect(created.name == "Gym Co")
        #expect(form.payeeID == created.id)
        #expect(form.payeeText == "Gym Co")
        #expect(form.createPayeeTitle == nil)
        #expect(form.save())
        #expect(try payees(scene).count == 1)
        #expect(try scene.repository.scheduleLedger().scheduledItems.contains { $0.payeeID == created.id })
    }

    @Test("Editing the text after a pick unpicks the payee; a transfer clears it")
    func unpick() throws {
        let scene = try ScheduledScene()
        let gym = Payee(name: "Gold's Gym", createdAt: scene.now)
        try scene.repository.savePayee(gym)
        let form = try form(scene)
        form.payeeText = "Gold's Gym"
        #expect(form.payeeID == gym.id)
        form.payeeText = "Gold's Gym East"
        #expect(form.payeeID == nil)
        form.payeeText = "Gold's Gym"
        form.type = .transfer
        #expect(form.payeeID == nil)
        #expect(form.payeeText.isEmpty)
    }
}
