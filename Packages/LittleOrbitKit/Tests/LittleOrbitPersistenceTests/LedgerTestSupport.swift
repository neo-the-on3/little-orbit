import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import XCTest

let posix = Locale(identifier: "en_US_POSIX")

/// A day after every transaction these tests create, so balances count all of them as current (D21).
let ledgerToday = CalendarDay(year: 2100, month: 1, day: 1)

typealias MakeRepository = @MainActor () throws -> any LedgerRepository

func decimal(_ value: String, file: StaticString = #filePath, line: UInt = #line) -> Decimal {
    guard let decimal = Decimal(string: value, locale: posix) else {
        XCTFail("Could not parse decimal \(value)", file: file, line: line)
        return 0
    }
    return decimal
}

func onMain(_ body: @MainActor () throws -> Void) rethrows {
    try MainActor.assumeIsolated(body)
}

@MainActor
final class TestClock {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

@MainActor
func assertLedgerAcceptance(make: MakeRepository) throws {
    try assertInvalidAmountsAreRejected(make: make)
    try assertSameTransferAccountIsRejected(make: make)
    try assertCrossCurrencyTransfer(make: make)
    try assertBalanceIsExact(make: make)
    try assertBalanceCountsOnlyTransactionsDatedUpToToday(make: make)
    try assertAtomicChangesAreAllOrNothing(make: make)
    try assertCreditCardOpeningBalanceReducesNetWorth(make: make)
    try assertNetWorthGroupsCurrenciesAndSkipsExcludedAccounts(make: make)
    try assertHiddenAccountStillCountsInNetWorth(make: make)
    try assertCategoryNestingIsOneLevel(make: make)
    try assertDeletingCategoryCanLeaveTransactionsUncategorised(make: make)
    try assertDeletingParentCategoryClearsSubcategoryTransactions(make: make)
    try assertScheduledOccurrenceIsRecordedOnce(make: make)
    try assertCurrencyLocksOnceTransactionsExist(make: make)
    try assertTransactionCannotChangeToOrFromTransfer(make: make)
    try assertTransactionsBeforeOpeningDateStillCount(make: make)
    try assertDeletedRecordsAreHiddenFromQueries(make: make)
    try assertSeedCategoriesAreIdempotent(make: make)
    try assertNamesAreTrimmedAndPayeesMerge(make: make)
    try assertPayeeReferenceCount(make: make)
    try assertSplitsMustSumToTheTransaction(make: make)
    try assertAttachmentLimit(make: make)
    try assertYenRejectsAFractionalAmount(make: make)
    try assertRefundsSurviveDeleteAndUndo(make: make)
}

@MainActor
private func assertInvalidAmountsAreRejected(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "10")
    for amount in ["0", "-1"] {
        let before = try repository.transactions().count
        XCTAssertThrowsError(
            try repository.saveTransaction(Transaction(amount: decimal(amount), accountID: account.id))
        ) { error in
            XCTAssertEqual(error as? LedgerValidationError, .invalidAmount)
        }
        XCTAssertEqual(try repository.transactions().count, before)
    }
}

@MainActor
private func assertSameTransferAccountIsRejected(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "0")
    XCTAssertThrowsError(
        try repository.saveTransaction(
            Transaction(
                type: .transfer,
                amount: decimal("5.00"),
                accountID: account.id,
                transferAccountID: account.id,
            )
        )
    ) { error in
        XCTAssertEqual(error as? LedgerValidationError, .sameTransferAccount)
    }
    XCTAssertTrue(try repository.transactions().isEmpty)
}

@MainActor
private func assertCrossCurrencyTransfer(make: MakeRepository) throws {
    let repository = try make()
    let india = Account(name: "India", currencyCode: "INR")
    let states = Account(name: "States", currencyCode: "USD")
    try repository.saveAccount(india)
    try repository.saveAccount(states)
    XCTAssertThrowsError(
        try repository.saveTransaction(
            Transaction(
                type: .transfer,
                amount: decimal("100.00"),
                accountID: india.id,
                transferAccountID: states.id,
            )
        )
    ) { error in
        XCTAssertEqual(error as? LedgerValidationError, .missingDestinationAmount)
    }
    try repository.saveTransaction(
        Transaction(
            type: .transfer,
            amount: decimal("100.00"),
            accountID: india.id,
            transferAccountID: states.id,
            destinationAmount: decimal("12.00"),
        )
    )
    XCTAssertEqual(try repository.balance(of: states.id, today: ledgerToday), decimal("12.00"))
    XCTAssertEqual(try repository.balance(of: india.id, today: ledgerToday), decimal("-100.00"))
}

@MainActor
private func assertBalanceIsExact(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, name: "Checking", opening: "1000.00")
    try repository.saveTransaction(
        Transaction(type: .expense, amount: decimal("250.10"), accountID: account.id)
    )
    try repository.saveTransaction(
        Transaction(type: .income, amount: decimal("0.20"), accountID: account.id)
    )
    XCTAssertEqual(try repository.balance(of: account.id, today: ledgerToday), decimal("750.10"))
}

@MainActor
private func assertCreditCardOpeningBalanceReducesNetWorth(make: MakeRepository) throws {
    let repository = try make()
    let bank = Account(name: "Bank", currencyCode: "USD", openingBalance: decimal("800.00"))
    let card = Account(
        name: "Card",
        type: .creditCard,
        currencyCode: "USD",
        openingBalance: OpeningBalance.signed(
            enteredAmount: decimal("500"),
            type: .creditCard,
            inCredit: false,
        ),
    )
    try repository.saveAccount(bank)
    try repository.saveAccount(card)
    let stored = try XCTUnwrap(try repository.accounts().first { $0.id == card.id })
    XCTAssertEqual(stored.openingBalance, decimal("-500"))
    XCTAssertEqual(try repository.netWorth(today: ledgerToday)["USD"], decimal("300") as Decimal?)
}

@MainActor
private func assertNetWorthGroupsCurrenciesAndSkipsExcludedAccounts(
    make: MakeRepository
) throws {
    let repository = try make()
    let included = Account(name: "Cash", currencyCode: "USD", openingBalance: decimal("40.00"))
    var excluded = Account(name: "Pot", currencyCode: "USD", openingBalance: decimal("1000.00"))
    excluded.includeInNetWorth = false
    let india = Account(name: "India", currencyCode: "INR", openingBalance: decimal("10.50"))
    try repository.saveAccount(included)
    try repository.saveAccount(excluded)
    try repository.saveAccount(india)
    let worth = try repository.netWorth(today: ledgerToday)
    XCTAssertEqual(worth["USD"], decimal("40.00") as Decimal?)
    XCTAssertEqual(worth["INR"], decimal("10.50") as Decimal?)
    XCTAssertNil(worth["EUR"])
}

@MainActor
private func assertHiddenAccountStillCountsInNetWorth(make: MakeRepository) throws {
    let repository = try make()
    var hidden = Account(name: "Sock", currencyCode: "USD", openingBalance: decimal("8.00"))
    hidden.isHidden = true
    try repository.saveAccount(hidden)
    XCTAssertEqual(try repository.netWorth(today: ledgerToday)["USD"], decimal("8.00") as Decimal?)
}

@MainActor
private func assertCategoryNestingIsOneLevel(make: MakeRepository) throws {
    let repository = try make()
    let parent = TransactionCategory(name: "Food", kind: .expense)
    let child = TransactionCategory(name: "Groceries", kind: .expense, parentID: parent.id)
    let grandchild = TransactionCategory(name: "Coffee", kind: .expense, parentID: child.id)
    try repository.saveCategory(parent)
    try repository.saveCategory(child)
    XCTAssertThrowsError(try repository.saveCategory(grandchild)) { error in
        XCTAssertEqual(error as? LedgerValidationError, .categoryNestingTooDeep)
    }
    XCTAssertThrowsError(try repository.saveCategory(TransactionCategory(name: "food", kind: .expense))) { error in
        XCTAssertEqual(error as? LedgerValidationError, .duplicateCategoryName)
    }
    XCTAssertEqual(try repository.categories().count, 2)
}

@MainActor
private func assertDeletingCategoryCanLeaveTransactionsUncategorised(
    make: MakeRepository
) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let category = TransactionCategory(name: "Food", kind: .expense)
    try repository.saveCategory(category)
    for _ in 0..<3 {
        try repository.saveTransaction(
            Transaction(type: .expense, amount: decimal("1.00"), accountID: account.id, categoryID: category.id)
        )
    }
    try repository.deleteCategory(id: category.id, reassigningTo: nil)
    let transactions = try repository.transactions()
    XCTAssertEqual(transactions.count, 3)
    XCTAssertTrue(transactions.allSatisfy { $0.categoryID == nil })
    XCTAssertTrue(try repository.categories().isEmpty)
}

@MainActor
private func assertDeletingParentCategoryClearsSubcategoryTransactions(
    make: MakeRepository
) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let parent = TransactionCategory(name: "Food", kind: .expense)
    let child = TransactionCategory(name: "Groceries", kind: .expense, parentID: parent.id)
    try repository.saveCategory(parent)
    try repository.saveCategory(child)
    try repository.saveTransaction(
        Transaction(type: .expense, amount: decimal("2.00"), accountID: account.id, categoryID: child.id)
    )
    try repository.deleteCategory(id: parent.id, reassigningTo: nil)
    let transactions = try repository.transactions()
    XCTAssertEqual(transactions.count, 1)
    XCTAssertNil(transactions[0].categoryID)
    XCTAssertTrue(try repository.categories().isEmpty)
}

@MainActor
private func assertScheduledOccurrenceIsRecordedOnce(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "50")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT") ?? .current
    let occurrence = try XCTUnwrap(
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))
    )
    let templateID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"))
    var draft = Transaction(
        type: .expense,
        amount: decimal("15.00"),
        accountID: account.id,
        scheduledTemplateID: templateID,
        scheduledOccurrenceDate: occurrence,
    )
    let first = try repository.recordScheduledOccurrence(draft)
    draft.id = UUID()
    let second = try repository.recordScheduledOccurrence(draft)
    XCTAssertEqual(first.id, second.id)
    XCTAssertEqual(try repository.transactions().count, 1)
}

@MainActor
private func assertCurrencyLocksOnceTransactionsExist(make: MakeRepository) throws {
    let repository = try make()
    var account = try saveCash(in: repository, opening: "20")
    try repository.saveTransaction(
        Transaction(type: .expense, amount: decimal("1.00"), accountID: account.id)
    )
    account.currencyCode = "EUR"
    XCTAssertThrowsError(try repository.saveAccount(account)) { error in
        XCTAssertEqual(error as? LedgerValidationError, .currencyLocked)
    }
    let stored = try XCTUnwrap(try repository.accounts().first { $0.id == account.id })
    XCTAssertEqual(stored.currencyCode, "USD")
}

@MainActor
private func assertTransactionCannotChangeToOrFromTransfer(make: MakeRepository) throws {
    let repository = try make()
    let source = try saveCash(in: repository, name: "A", opening: "30")
    let destination = try saveCash(in: repository, name: "B", opening: "0")
    var expense = Transaction(type: .expense, amount: decimal("3.00"), accountID: source.id)
    try repository.saveTransaction(expense)
    expense.type = .transfer
    expense.transferAccountID = destination.id
    XCTAssertThrowsError(try repository.saveTransaction(expense)) { error in
        XCTAssertEqual(error as? LedgerValidationError, .transactionTypeChangeNotAllowed)
    }
    let stored = try XCTUnwrap(try repository.transactions().first)
    XCTAssertEqual(stored.type, .expense)
}

@MainActor
private func assertTransactionsBeforeOpeningDateStillCount(make: MakeRepository) throws {
    let repository = try make()
    let opening = Date(timeIntervalSince1970: 1_800_000_000)
    let account = Account(
        name: "Cash",
        currencyCode: "USD",
        openingBalance: decimal("10.00"),
        openingDate: opening,
    )
    try repository.saveAccount(account)
    try repository.saveTransaction(
        Transaction(
            type: .expense,
            amount: decimal("4.00"),
            date: opening.addingTimeInterval(-86_400),
            accountID: account.id,
        )
    )
    XCTAssertEqual(try repository.balance(of: account.id, today: ledgerToday), decimal("6.00"))
}

@MainActor
private func assertDeletedRecordsAreHiddenFromQueries(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "25.00")
    var expense = Transaction(type: .expense, amount: decimal("5.00"), accountID: account.id)
    expense.deletedAt = Date(timeIntervalSince1970: 10)
    try repository.saveTransaction(expense)
    XCTAssertTrue(try repository.transactions().isEmpty)
    XCTAssertEqual(try repository.balance(of: account.id, today: ledgerToday), decimal("25.00"))
}

@MainActor
private func assertSeedCategoriesAreIdempotent(make: MakeRepository) throws {
    let repository = try make()
    try repository.seedDefaultCategories()
    try repository.seedDefaultCategories()
    let categories = try repository.categories()
    XCTAssertEqual(categories.count, DefaultCategories.make().count)
    XCTAssertEqual(categories.filter { $0.id == DefaultCategoryID.food }.count, 1)
    XCTAssertEqual(categories.first { $0.id == DefaultCategoryID.food }?.name, "Food & Dining")
    XCTAssertEqual(
        categories.first { $0.id == DefaultCategoryID.groceries }?.parentID,
        DefaultCategoryID.food,
    )
    let insurance = categories.filter { $0.id == DefaultCategoryID.insurance }
    XCTAssertEqual(insurance.count, 1)
    XCTAssertEqual(insurance.first?.name, "Insurance")
    XCTAssertEqual(insurance.first?.kind, .expense)
    XCTAssertNil(insurance.first?.parentID)
    XCTAssertFalse(categories.contains { $0.name == "Uncategorised" || $0.name == "Transfer" })
}

@MainActor
private func assertNamesAreTrimmedAndPayeesMerge(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "10")
    try repository.savePayee(Payee(name: "  Cafe  "))
    let payee = try XCTUnwrap(try repository.payees().first)
    XCTAssertEqual(payee.name, "Cafe")
    XCTAssertThrowsError(try repository.savePayee(Payee(name: "cafe"))) { error in
        XCTAssertEqual(error as? LedgerValidationError, .duplicatePayeeName)
    }
    let other = Payee(name: "Diner")
    try repository.savePayee(other)
    try repository.saveTransaction(
        Transaction(type: .expense, amount: decimal("1.00"), accountID: account.id, payeeID: other.id)
    )
    try repository.mergePayees(other.id, into: payee.id)
    XCTAssertEqual(try repository.payees().map(\.id), [payee.id])
    XCTAssertEqual(try repository.transactions().first?.payeeID, payee.id)
}

@MainActor
private func assertSplitsMustSumToTheTransaction(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "10")
    let food = TransactionCategory(name: "Food", kind: .expense)
    try repository.saveCategory(food)
    let home = TransactionCategory(name: "Home", kind: .expense)
    try repository.saveCategory(home)
    let transaction = Transaction(type: .expense, amount: decimal("10.00"), accountID: account.id)
    try repository.saveTransaction(transaction)
    XCTAssertThrowsError(
        try repository.replaceSplits(
            [
                TransactionSplit(categoryID: food.id, amount: decimal("3.00")),
                TransactionSplit(categoryID: home.id, amount: decimal("6.00")),
            ],
            for: transaction.id,
        )
    ) { error in
        XCTAssertEqual(error as? LedgerValidationError, .splitRuleBroken(.linesDoNotMatchTotal))
    }
    XCTAssertTrue(try repository.splits(for: transaction.id).isEmpty)
    try repository.replaceSplits(
        [
            TransactionSplit(categoryID: food.id, amount: decimal("4.00")),
            TransactionSplit(categoryID: home.id, amount: decimal("6.00")),
        ],
        for: transaction.id,
    )
    let splits = try repository.splits(for: transaction.id)
    XCTAssertEqual(splits.count, 2)
    XCTAssertEqual(splits.reduce(Decimal(0)) { $0 + $1.amount }, decimal("10.00"))
}

@MainActor
private func assertAttachmentLimit(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "10")
    let transaction = Transaction(type: .expense, amount: decimal("1.00"), accountID: account.id)
    try repository.saveTransaction(transaction)
    let tooLarge = Attachment(
        transactionID: transaction.id,
        fileName: "receipt.jpg",
        contentType: "public.jpeg",
        data: Data(count: 50 * 1_024 * 1_024 + 1),
    )
    XCTAssertThrowsError(try repository.saveAttachment(tooLarge)) { error in
        XCTAssertEqual(error as? LedgerValidationError, .attachmentTooLarge)
    }
    let payload = Data("receipt".utf8)
    try repository.saveAttachment(
        Attachment(
            transactionID: transaction.id,
            fileName: "receipt.txt",
            contentType: "public.plain-text",
            data: payload,
        )
    )
    let stored = try XCTUnwrap(try repository.attachments(for: transaction.id).first)
    XCTAssertEqual(stored.data, payload)
    XCTAssertEqual(stored.byteSize, Int64(payload.count))
}

@MainActor
func assertUpdatedAtBumps(_ repository: any LedgerRepository, advance: () -> Void) throws {
    let created = Date(timeIntervalSince1970: 1_000)
    let account = Account(name: "Cash", currencyCode: "USD", createdAt: created, updatedAt: created)
    try repository.saveAccount(account)
    advance()
    try repository.saveAccount(account)
    let stored = try XCTUnwrap(try repository.accounts().first)
    XCTAssertEqual(stored.createdAt, created)
    XCTAssertEqual(stored.updatedAt, Date(timeIntervalSince1970: 2_000))
}

@MainActor
private func assertYenRejectsAFractionalAmount(make: MakeRepository) throws {
    let repository = try make()
    let yen = Account(name: "Yen", currencyCode: "JPY")
    try repository.saveAccount(yen)
    XCTAssertThrowsError(
        try repository.saveTransaction(Transaction(amount: decimal("1.5"), accountID: yen.id))
    ) { error in
        XCTAssertEqual(error as? LedgerValidationError, .tooManyDecimalPlaces)
    }
    XCTAssertTrue(try repository.transactions().isEmpty)
}

@MainActor
func saveCash(
    in repository: any LedgerRepository,
    name: String = "Cash",
    opening: String,
) throws -> Account {
    let account = Account(name: name, currencyCode: "USD", openingBalance: decimal(opening))
    try repository.saveAccount(account)
    return account
}
