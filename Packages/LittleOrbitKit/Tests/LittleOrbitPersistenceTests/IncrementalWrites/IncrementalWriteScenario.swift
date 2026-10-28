import Foundation
import LittleOrbitDomain

/// The changes #235's incremental write is checked against the whole-store write with: import and Undo Import,
/// a transaction saved, edited and deleted (and put back, as Undo does), scheduled-item edits and settlements,
/// and the account, category, payee, tag, split, attachment and budget settings. Each runs on the fixture; the
/// part `measured` wraps is the change compared.
@MainActor
enum IncrementalWriteScenario: String, CaseIterable {
    case importCommit
    case undoImport
    case insertTransaction
    case editTransaction
    case deleteTransaction
    case restoreDeletedTransaction
    case moveSplitTransactionToOtherCurrency
    case editScheduledItem
    case payScheduledOccurrence
    case skipScheduledOccurrence
    case deleteScheduledItem
    case editAccount
    case changeAccountCurrency
    case deleteAccount
    case reorderAndArchiveCategories
    case mergeCategories
    case deleteCategory
    case mergePayees
    case deleteTag
    case replaceSplits
    case saveAndDeleteAttachment
    case changeBudgetLimit
    case deleteBudget

    typealias Measured = (() throws -> Void) throws -> Void

    func run(
        on repository: IncrementalWriteRepository,
        _ fixture: IncrementalWriteFixture,
        measured: Measured,
    ) throws {
        switch self {
        case .importCommit:
            try measured { _ = try IncrementalWriteFixture.importRows(into: repository) }
        case .undoImport:
            let receipt = try IncrementalWriteFixture.importRows(into: repository)
            try measured { try ImportUseCases(repository: repository).ledger.undo(receipt) }
        case .insertTransaction, .editTransaction, .deleteTransaction, .restoreDeletedTransaction,
            .moveSplitTransactionToOtherCurrency:
            try runTransactionChange(on: repository, fixture, measured: measured)
        case .editScheduledItem, .payScheduledOccurrence, .skipScheduledOccurrence, .deleteScheduledItem:
            try runScheduledChange(on: repository, fixture, measured: measured)
        default:
            try runSettingsChange(on: repository, fixture, measured: measured)
        }
    }

    private func runTransactionChange(
        on repository: IncrementalWriteRepository,
        _ fixture: IncrementalWriteFixture,
        measured: Measured,
    ) throws {
        switch self {
        case .insertTransaction:
            let lunch = Transaction(
                amount: 250,
                date: IncrementalWriteFixture.created.addingTimeInterval(86_400),
                timeZoneID: IncrementalWriteFixture.zone,
                accountID: fixture.travel.id,
                categoryID: fixture.food.id,
                payeeID: fixture.corner.id,
                details: "Lunch",
                tagIDs: [fixture.trip.id],
            )
            try measured { try repository.saveTransaction(lunch) }
        case .editTransaction:
            var groceries = fixture.groceries
            groceries.payeeID = fixture.cinema.id
            groceries.tagIDs = [fixture.trip.id]
            groceries.note = "Edited"
            var movie = fixture.movie
            movie.categoryID = fixture.snacks.id
            movie.amount = 120
            movie.tagIDs = [fixture.weekend.id]
            try measured {
                try repository.saveTransaction(groceries)
                try repository.saveTransaction(movie)
            }
        case .deleteTransaction:
            try measured { try repository.deleteTransaction(id: fixture.groceries.id) }
        case .moveSplitTransactionToOtherCurrency:
            // #265: its splits are stored in its account's currency, so moving to one with other decimal places
            // writes them again; an edit in the same currency (`editTransaction`) leaves them as stored.
            let yen = Account(name: "Yen Wallet", type: .cash, currencyCode: "JPY", sortOrder: 3)
            try repository.saveAccount(yen)
            var groceries = fixture.groceries
            groceries.accountID = yen.id
            try measured { try repository.saveTransaction(groceries) }
        default:
            // As Undo of a delete: the attachment comes back with its bytes, read before the delete.
            let attachments = try repository.attachments(for: fixture.groceries.id)
            let splits = try repository.splits(for: fixture.groceries.id)
            try repository.deleteTransaction(id: fixture.groceries.id)
            try measured {
                try repository.atomically {
                    try repository.saveTransaction(fixture.groceries)
                    try repository.replaceSplits(splits, for: fixture.groceries.id)
                    for attachment in attachments {
                        try repository.saveAttachment(attachment)
                    }
                }
            }
        }
    }

    private func runScheduledChange(
        on repository: IncrementalWriteRepository,
        _ fixture: IncrementalWriteFixture,
        measured: Measured,
    ) throws {
        let next = CalendarDay(year: 2026, month: 12, day: 1)
        switch self {
        case .editScheduledItem:
            var edited =
                try repository.scheduleLedger().scheduledItems.first { $0.id == fixture.gym.id }
                ?? fixture.gym
            edited.amount = 1500
            edited.details = "Membership, yearly"
            edited.notifiesWhenDue = true
            try measured {
                try repository.saveScheduledItem(edited, today: next, now: IncrementalWriteFixture.created)
            }
        case .payScheduledOccurrence:
            try measured {
                _ = try repository.settleScheduledOccurrence(
                    .pay(itemID: fixture.gym.id, occurrence: next, postedOn: next)
                )
            }
        case .skipScheduledOccurrence:
            try measured {
                _ = try repository.settleScheduledOccurrence(.skip(itemID: fixture.gym.id, occurrence: next))
            }
        default:
            try measured { try repository.deleteScheduledItem(id: fixture.gym.id) }
        }
    }

    private func runSettingsChange(
        on repository: IncrementalWriteRepository,
        _ fixture: IncrementalWriteFixture,
        measured: Measured,
    ) throws {
        switch self {
        case .editAccount:
            var edited = fixture.savings
            edited.name = "Household"
            edited.isHidden = true
            edited.sortOrder = 5
            try measured { try repository.saveAccount(edited) }
        case .deleteAccount:
            try measured { try repository.deleteAccount(id: fixture.travel.id) }
        case .changeAccountCurrency:
            try runCurrencyChange(on: repository, fixture, measured: measured)
        case .reorderAndArchiveCategories:
            try measured {
                try repository.reorderCategories([fixture.rent.id, fixture.food.id])
                try repository.archiveCategory(id: fixture.rent.id, archived: true)
            }
        case .mergeCategories:
            try measured { try repository.mergeCategories(fixture.snacks.id, into: fixture.food.id) }
        case .deleteCategory:
            try measured { try repository.deleteCategory(id: fixture.snacks.id, reassigningTo: fixture.rent.id) }
        case .mergePayees:
            try measured { try repository.mergePayees(fixture.cinema.id, into: fixture.corner.id) }
        case .deleteTag:
            try measured { try repository.deleteTag(id: fixture.weekend.id) }
        default:
            try runRecordChange(on: repository, fixture, measured: measured)
        }
    }

    /// An account with no live transactions, only a deleted one, moved to a currency with other decimal places.
    /// A scheduled item locks the currency at the store (D410.1), so its item is deleted first, as D410.3 asks;
    /// the deleted transaction was removed outright, so only the account is stored again.
    private func runCurrencyChange(
        on repository: IncrementalWriteRepository,
        _ fixture: IncrementalWriteFixture,
        measured: Measured,
    ) throws {
        var wallet = Account(name: "Yen Wallet", type: .cash, currencyCode: "INR", sortOrder: 3)
        try repository.saveAccount(wallet)
        let fare = Transaction(
            amount: 1500,
            date: IncrementalWriteFixture.created,
            timeZoneID: IncrementalWriteFixture.zone,
            accountID: wallet.id,
            details: "Fare",
        )
        try repository.saveTransaction(fare)
        try repository.deleteTransaction(id: fare.id)
        let pass = ScheduledItem(
            type: .expense,
            amount: 3000,
            accountID: wallet.id,
            details: "Rail pass",
            startDay: IncrementalWriteFixture.start,
            timeZoneID: IncrementalWriteFixture.zone,
            createdAt: IncrementalWriteFixture.created,
        )
        try repository.saveScheduledItem(
            pass,
            today: IncrementalWriteFixture.start,
            now: IncrementalWriteFixture.created,
        )
        try repository.deleteScheduledItem(id: pass.id)
        wallet.currencyCode = "JPY"
        try measured { try repository.saveAccount(wallet) }
    }

    private func runRecordChange(
        on repository: IncrementalWriteRepository,
        _ fixture: IncrementalWriteFixture,
        measured: Measured,
    ) throws {
        switch self {
        case .replaceSplits:
            let split = TransactionSplit(transactionID: fixture.groceries.id, categoryID: fixture.rent.id, amount: 450)
            try measured { try repository.replaceSplits([split], for: fixture.groceries.id) }
        case .saveAndDeleteAttachment:
            let note = Attachment(
                transactionID: fixture.movie.id,
                fileName: "ticket.pdf",
                contentType: "application/pdf",
                data: Data("made-up ticket".utf8),
            )
            try measured {
                try repository.saveAttachment(note)
                try repository.deleteAttachment(id: fixture.receipt.id)
            }
        case .changeBudgetLimit:
            try measured {
                try repository.changeBudgetLimit(
                    of: fixture.budget.id,
                    to: 6000,
                    fromPeriodStartingOn: CalendarDay(year: 2026, month: 12, day: 1),
                )
            }
        default:
            try measured { try repository.deleteBudget(id: fixture.budget.id) }
        }
    }
}
