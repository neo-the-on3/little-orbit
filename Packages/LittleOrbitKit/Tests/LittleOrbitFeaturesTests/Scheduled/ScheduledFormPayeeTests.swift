import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Scheduled form's payee field (#197): the #23 autocomplete, with a "Create “‹text›”" or "Use archived
/// “‹name›”" row that marks the payee pending, stored when the item is saved (D350.1, D351.2).
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

    @Test("D347.2: unmatched text shows the Create hint and Save waits; an exact name never shows it")
    func hintAndSave() throws {
        let scene = try ScheduledScene()
        try scene.repository.savePayee(Payee(name: "Gold's Gym", createdAt: scene.now))
        let form = try form(scene)
        form.amountText = "1200"
        form.payeeText = " Gym Co "
        #expect(form.payeeHint == "Choose “Create Gym Co” to add this payee, or clear the field.")
        #expect(!form.canSave)
        #expect(!form.save())
        form.payeeText = "gold's gym"
        #expect(form.payeeHint == nil)
        #expect(form.canSave)
        form.payeeText = ""
        #expect(form.payeeHint == nil)
        #expect(form.canSave)
    }

    @Test("D350.1: Create only marks the payee pending; Save creates it once, Cancel creates nothing")
    func createOnSave() throws {
        let scene = try ScheduledScene()
        var form = try form(scene)
        form.amountText = "1200"
        form.payeeText = " Gym Co "
        form.createPayee()
        #expect(form.payeeText == "Gym Co")
        #expect(form.createPayeeTitle == nil)
        #expect(form.payeeHint == nil)
        #expect(try payees(scene).isEmpty)
        // Cancel: the form goes and nothing is stored.
        form = try self.form(scene)
        #expect(try payees(scene).isEmpty)

        form.amountText = "1200"
        form.payeeText = "Gym Co"
        form.createPayee()
        #expect(form.save())
        let created = try #require(try payees(scene).first)
        #expect(created.name == "Gym Co")
        #expect(try payees(scene).count == 1)
        #expect(try scene.repository.scheduleLedger().scheduledItems.contains { $0.payeeID == created.id })
    }

    @Test(
        "D351.2, D352.1: an archived payee's name shows Use archived, Archived payee and its hint; Save unarchives it"
    )
    func archivedPayee() throws {
        let scene = try ScheduledScene()
        let shop = Payee(name: "Old Shop", isArchived: true, createdAt: scene.now)
        try scene.repository.savePayee(shop)
        let form = try form(scene)
        form.amountText = "1200"
        form.payeeText = " old shop "
        #expect(form.payeeID == nil)
        #expect(form.createPayeeTitle == nil)
        #expect(form.useArchivedPayeeTitle == "Use archived “Old Shop”")
        #expect(form.useArchivedPayeeSubtitle == "Archived payee")
        #expect(form.payeeHint == "Choose “Use archived Old Shop” to use this payee, or clear the field.")
        #expect(!form.canSave)
        form.useArchivedPayee()
        #expect(form.payeeText == "Old Shop")
        #expect(form.canSave)
        #expect(try payees(scene).first?.isArchived == true)
        #expect(form.save())
        #expect(try payees(scene).map(\.isArchived) == [false])
        #expect(try scene.repository.scheduleLedger().scheduledItems.first?.payeeID == shop.id)
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
