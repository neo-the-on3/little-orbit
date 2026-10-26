import Foundation
import LittleOrbitDomain

typealias IncrementalWriteRepository = any LedgerRepository & ScheduleRepository & BudgetRepository
    & LedgerBackupSource

/// A small made-up ledger with every record type and link (#235): two accounts, a category with a
/// subcategory, payees with a default category, tags, a split expense with tags and an attachment, a
/// transfer, a budget with a limit, and a scheduled item with a skipped occurrence. Dated in `Asia/Kolkata`.
@MainActor
struct IncrementalWriteFixture {
    static let zone = "Asia/Kolkata"
    static let created = Date(timeIntervalSince1970: 1_790_000_000)
    static let start = CalendarDay(year: 2026, month: 11, day: 1)
    static let receiptBytes = Data("made-up receipt".utf8)

    let savings: Account
    let travel: Account
    let food: TransactionCategory
    let snacks: TransactionCategory
    let rent: TransactionCategory
    let corner: Payee
    let cinema: Payee
    let weekend: Tag
    let trip: Tag
    let groceries: Transaction
    let movie: Transaction
    let transfer: Transaction
    let receipt: Attachment
    let budget: Budget
    let gym: ScheduledItem

    static func seed(into repository: IncrementalWriteRepository) throws -> Self {
        let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
        let travel = Account(name: "Travel Card", type: .checking, currencyCode: "INR", sortOrder: 2)
        try repository.saveAccount(savings)
        try repository.saveAccount(travel)
        let food = TransactionCategory(name: "Food", kind: .expense, sortOrder: 1)
        let snacks = TransactionCategory(name: "Snacks", kind: .expense, parentID: food.id, sortOrder: 2)
        let rent = TransactionCategory(name: "Rent", kind: .expense, sortOrder: 3)
        for category in [food, snacks, rent] {
            try repository.saveCategory(category)
        }
        let corner = Payee(name: "Corner Shop", defaultCategoryID: food.id)
        let cinema = Payee(name: "Cinema Hall")
        try repository.savePayee(corner)
        try repository.savePayee(cinema)
        let weekend = Tag(name: "Weekend")
        let trip = Tag(name: "Trip", sortOrder: 1)
        try repository.saveTag(weekend)
        try repository.saveTag(trip)

        let groceries = Transaction(
            type: .expense,
            amount: 450,
            date: created,
            timeZoneID: zone,
            accountID: savings.id,
            payeeID: corner.id,
            details: "Groceries",
            tagIDs: [weekend.id, trip.id],
        )
        let movie = Transaction(
            type: .expense,
            amount: 90,
            date: created.addingTimeInterval(3600),
            timeZoneID: zone,
            accountID: savings.id,
            categoryID: food.id,
            payeeID: cinema.id,
            details: "Show",
        )
        let transfer = Transaction(
            type: .transfer,
            amount: 1000,
            date: created.addingTimeInterval(7200),
            timeZoneID: zone,
            accountID: savings.id,
            transferAccountID: travel.id,
        )
        for transaction in [groceries, movie, transfer] {
            try repository.saveTransaction(transaction)
        }
        try repository.replaceSplits(
            [
                TransactionSplit(transactionID: groceries.id, categoryID: food.id, amount: 300, sortOrder: 0),
                TransactionSplit(transactionID: groceries.id, categoryID: snacks.id, amount: 150, sortOrder: 1),
            ],
            for: groceries.id,
        )
        let receipt = Attachment(
            transactionID: groceries.id,
            fileName: "receipt.jpg",
            contentType: "image/jpeg",
            data: receiptBytes,
        )
        try repository.saveAttachment(receipt)

        let (budget, gym) = try seedPlans(into: repository, savings: savings, food: food, rent: rent, payee: cinema)
        return Self(
            savings: savings,
            travel: travel,
            food: food,
            snacks: snacks,
            rent: rent,
            corner: corner,
            cinema: cinema,
            weekend: weekend,
            trip: trip,
            groceries: groceries,
            movie: movie,
            transfer: transfer,
            receipt: receipt,
            budget: budget,
            gym: gym,
        )
    }

    /// #235 N2: a new attachment on `movie` that came without its bytes (`data` empty, `byteSize` not 0). The
    /// domain never writes one: `saveAttachment` sets `byteSize` to `data.count`.
    func bytelessTicket() -> Attachment {
        Attachment(transactionID: movie.id, fileName: "ticket.pdf", contentType: "application/pdf", byteSize: 12)
    }

    /// The budget on Food and the scheduled Membership, with its first occurrence skipped.
    private static func seedPlans(
        into repository: IncrementalWriteRepository,
        savings: Account,
        food: TransactionCategory,
        rent: TransactionCategory,
        payee: Payee,
    ) throws -> (Budget, ScheduledItem) {
        let budget = Budget(
            name: "Food",
            currencyCode: "INR",
            categoryIDs: [food.id],
            startDay: start,
            limit: 5000,
            createdAt: created,
        )
        try repository.saveBudget(budget)
        let gym = ScheduledItem(
            type: .expense,
            amount: 1200,
            accountID: savings.id,
            categoryID: rent.id,
            payeeID: payee.id,
            details: "Membership",
            startDay: start,
            timeZoneID: zone,
            createdAt: created,
        )
        try repository.saveScheduledItem(gym, today: start, now: created)
        _ = try repository.settleScheduledOccurrence(.skip(itemID: gym.id, occurrence: start))
        return (budget, gym)
    }

    /// Four made-up rows that create an account and two payees.
    static let importFile = """
        Date,Amount,Account,Payee,Description
        2026-10-20,-450,Everyday Savings,Corner Shop,Milk
        2026-10-21,-90,Everyday Savings,Kiosk,Tea
        2026-10-22,-1200,Wallet,Gym,Membership
        2026-10-23,-60,Wallet,Kiosk,Snack
        """

    static func importRows(into repository: IncrementalWriteRepository) throws -> ImportReceipt {
        let useCases = ImportUseCases(repository: repository)
        let file = try useCases.pipeline.open(Data(importFile.utf8))
        let settings = ImportReadSettings(
            mapping: file.suggestedMapping,
            dateOrder: .yearMonthDay,
            decimalSeparator: .period,
            timeZone: TimeZone(identifier: zone) ?? .gmt,
        )
        let preview = useCases.pipeline.preview(
            rows: useCases.pipeline.rows(in: file, settings: settings),
            ledger: try useCases.ledger.ledger(),
            choices: ImportChoices(),
            settings: settings,
            defaultCurrency: "INR",
        )
        return try useCases.ledger.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
    }
}
