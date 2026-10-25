import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D372 (Product Manager, final wording; supersedes the D371 draft): the account delete confirmation says how many
/// scheduled occurrences moved to the account go back to their items' accounts. Made-up data.
@MainActor
@Suite("Account delete confirmation: occurrences moved to the account (D372)")
struct AccountDeleteMovedOccurrencesTests {
    private let november = CalendarDay(year: 2026, month: 11, day: 1)
    private let december = CalendarDay(year: 2026, month: 12, day: 1)
    private let one = "1 scheduled occurrence moved to this account will go back to its item’s account."

    /// Rent on Everyday Savings from 1 Nov; today is 20 Oct. `moved` occurrences alone pay from Long Term Fund.
    private func scene(moving moved: [CalendarDay]) throws -> (ScheduledScene, UUID) {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 11)
        try scene.add(rent)
        for day in moved {
            let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
            var form = item.resolved(for: day)
            form.occurrences = item.occurrences
            form.accountID = scene.fund.id
            _ = try scene.useCases.manage.update(
                form,
                editing: ScheduledOccurrenceSave(occurrence: day, dueDay: day, scope: .thisOccurrence),
                payee: nil,
            )
        }
        return (scene, rent.id)
    }

    private func accounts(_ scene: ScheduledScene) -> AccountsViewModel {
        let model = AccountsViewModel(
            useCases: AccountUseCases(
                repository: scene.repository,
                defaultCurrency: "INR",
                timeZone: TimeZone(identifier: ScheduledScene.zone)!,
                now: { [unowned scene] in scene.now },
            ),
            plannedItems: scene.feature(),
            locale: Locale(identifier: "en_IN"),
        )
        model.load()
        return model
    }

    private func message(_ scene: ScheduledScene) throws -> String {
        try #require(accounts(scene).deletePrompt(accountID: scene.fund.id)).message
    }

    @Test("0: no occurrence moved to the account leaves the #23 message as it was")
    func none() throws {
        let (scene, _) = try scene(moving: [])
        #expect(try scene.useCases.load.movedOccurrenceCount(toAccount: scene.fund.id) == 0)
        #expect(
            try message(scene)
                == "This account has no transactions. You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth."
        )
    }

    @Test("1: the sentence follows the first, in the slot, with the same words on iOS and the Mac")
    func single() throws {
        let (scene, _) = try scene(moving: [november])
        #expect(try scene.useCases.load.movedOccurrenceCount(toAccount: scene.fund.id) == 1)
        // The prompt has no platform input: the iOS alert and the Mac alert show this one string.
        #expect(
            try message(scene)
                == "This account has no transactions. \(one) You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth."
        )
        // The item's own account isn't counted: only occurrences moved to the deleted one.
        #expect(try scene.useCases.load.movedOccurrenceCount(toAccount: scene.account.id) == 0)
    }

    @Test("N: two occurrences read the plural; a recorded or skipped one isn't counted")
    func several() throws {
        let (scene, id) = try scene(moving: [november, december])
        #expect(
            try message(scene)
                .contains("2 scheduled occurrences moved to this account will go back to their items’ accounts.")
        )
        scene.now = ScheduledScene.date(november)
        _ = try scene.useCases.manage.payNow(itemID: id, occurrence: november)
        #expect(try scene.useCases.load.movedOccurrenceCount(toAccount: scene.fund.id) == 1)
        try scene.useCases.manage.skip(itemID: id, occurrence: december)
        #expect(try scene.useCases.load.movedOccurrenceCount(toAccount: scene.fund.id) == 0)
    }

    @Test("A To account moved to the account counts, and a transfer's message keeps the sentence after the first")
    func toAccount() throws {
        let scene = try ScheduledScene()
        var transfer = scene.item("Savings", day: 1, month: 11)
        transfer.type = .transfer
        transfer.categoryID = nil
        transfer.transferAccountID = scene.account.id
        transfer.accountID = scene.fund.id
        let third = Account(name: "Holiday Fund", currencyCode: "INR", sortOrder: 2)
        try scene.repository.saveAccount(third)
        try scene.add(transfer)
        let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        var form = item.resolved(for: november)
        form.occurrences = item.occurrences
        form.transferAccountID = third.id
        _ = try scene.useCases.manage.update(
            form,
            editing: ScheduledOccurrenceSave(occurrence: november, dueDay: november, scope: .thisOccurrence),
            payee: nil,
        )
        #expect(try scene.useCases.load.movedOccurrenceCount(toAccount: third.id) == 1)
        let prompt = try #require(accounts(scene).deletePrompt(accountID: third.id))
        #expect(prompt.message.hasPrefix("This account has no transactions. \(one) "))
    }

    @Test("The slot: D288's sentence comes first, then D372's; each is its own entry, and none leaves no slot")
    func ordering() {
        let d288 = "Its scheduled item is deleted."
        let d372 = AccountDeletePrompt.movedOccurrencesSentence(1)
        #expect(AccountDeletePrompt.slot([d288, d372]) == "\(d288) \(one)")
        #expect(AccountDeletePrompt.slot([nil, d372]) == one)
        #expect(AccountDeletePrompt.slot([d288, nil]) == d288)
        #expect(AccountDeletePrompt.slot([nil, AccountDeletePrompt.movedOccurrencesSentence(0)]) == nil)
        #expect(
            AccountDeletePrompt.message(transactions: 3, transfers: 0, scheduled: "\(d288) \(one)")
                == "This deletes 3 transactions. \(d288) \(one) Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth."
        )
    }

    @Test("Undo Delete Account gives the moved occurrence its own account back")
    func undoDeleteAccount() throws {
        let (scene, id) = try scene(moving: [november])
        let model = accounts(scene)
        let confirmation = AccountDeleteConfirmation(model: model)
        confirmation.request(accountID: scene.fund.id)
        #expect(confirmation.prompt?.message.contains(one) == true)
        let change = try #require(confirmation.confirm())
        let followed = try #require(try scene.useCases.load.listing().item(id))
        #expect(followed.resolved(for: november).accountID == scene.account.id)
        let useCases = TransactionUseCases(repository: scene.repository, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases)
        window.history.record(change)
        window.history.undo()
        let back = try #require(try scene.useCases.load.listing().item(id))
        #expect(back.resolved(for: november).accountID == scene.fund.id)
        #expect(try scene.useCases.load.movedOccurrenceCount(toAccount: scene.fund.id) == 1)
    }
}
