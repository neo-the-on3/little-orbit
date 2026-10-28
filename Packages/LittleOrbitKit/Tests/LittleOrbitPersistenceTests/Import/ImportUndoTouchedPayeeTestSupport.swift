import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import XCTest

/// Made-up “riverstone_oct.csv” for D384: imported into Everyday Savings, it creates Corner Bakery, StreamBox and
/// Lantern Tea House, and uses City Gym, which was there before. Its StreamBox rows carry the Food category, so
/// the import's own save sets StreamBox's default category (the `touchPayee` capture case, #254).
@MainActor
private enum TouchedPayeeFixture {
    static let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
    static let text = """
        Date,Amount,Account,Category,Payee,Description
        2026-10-20,-450,Everyday Savings,,Corner Bakery,Bread
        2026-10-21,-199,Everyday Savings,Food,StreamBox,Subscription
        2026-10-22,-320,Everyday Savings,,Lantern Tea House,Tea
        2026-10-23,-1500,Everyday Savings,,City Gym,Membership
        2026-10-24,-75,Everyday Savings,Food,StreamBox,Add-on
        """

    @MainActor
    struct Ledger {
        let repository: any LedgerRepository & ScheduleRepository & LedgerBackupSource
        let account: Account
        let treats: TransactionCategory
        let before: LedgerSnapshot
        var receipt: ImportReceipt

        func payee(_ name: String) throws -> Payee {
            try XCTUnwrap(try repository.payees().first { $0.name == name }, name)
        }

        func save(_ payee: Payee) throws {
            try repository.savePayee(payee)
        }
    }

    static func ledger(_ make: MakeScheduleRepository) throws -> Ledger {
        let repository = try make()
        let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
        try repository.saveAccount(account)
        try repository.saveCategory(TransactionCategory(name: "Food", kind: .expense, sortOrder: 1))
        let treats = TransactionCategory(name: "Treats", kind: .expense, sortOrder: 2)
        try repository.saveCategory(treats)
        let gym = Payee(name: "City Gym")
        try repository.savePayee(gym)
        var mine = Transaction(type: .expense, amount: 60, timeZoneID: zone.identifier, accountID: account.id)
        mine.payeeID = gym.id
        try repository.saveTransaction(mine)
        let before = try repository.ledgerSnapshot()
        let receipt = try commit(into: repository)
        return Ledger(repository: repository, account: account, treats: treats, before: before, receipt: receipt)
    }

    static func commit(into repository: any LedgerRepository) throws -> ImportReceipt {
        let useCases = ImportUseCases(repository: repository)
        let file = try useCases.pipeline.open(Data(text.utf8))
        let settings = ImportReadSettings(
            mapping: file.suggestedMapping,
            dateOrder: .yearMonthDay,
            decimalSeparator: .period,
            timeZone: zone,
        )
        let preview = useCases.pipeline.preview(
            rows: useCases.pipeline.rows(in: file, settings: settings),
            ledger: try useCases.ledger.ledger(),
            choices: ImportChoices(),
            settings: settings,
            defaultCurrency: "INR",
        )
        return try useCases.ledger.commit(preview, selection: preview.defaultSelection, fileName: "riverstone_oct.csv")
    }

    /// What happens between the import and Undo Import, and the created payees Undo Import must keep.
    struct Case {
        let name: String
        let kept: Set<String>
        let touch: @MainActor (inout Ledger) throws -> Void
    }

    static let cases: [Case] = [
        Case(name: "untouched, so all three go", kept: []) { _ in },
        Case(name: "Corner Bakery renamed", kept: ["Corner Bakery & Café"]) { ledger in
            var payee = try ledger.payee("Corner Bakery")
            payee.name = "Corner Bakery & Café"
            try ledger.save(payee)
        },
        Case(name: "Corner Bakery given a default category", kept: ["Corner Bakery"]) { ledger in
            var payee = try ledger.payee("Corner Bakery")
            XCTAssertNil(payee.defaultCategoryID)
            payee.defaultCategoryID = ledger.treats.id
            try ledger.save(payee)
        },
        Case(name: "StreamBox's default category changed", kept: ["StreamBox"]) { ledger in
            var payee = try ledger.payee("StreamBox")
            XCTAssertNotNil(payee.defaultCategoryID, "the import's rows set it")
            payee.defaultCategoryID = ledger.treats.id
            try ledger.save(payee)
        },
        Case(name: "StreamBox archived", kept: ["StreamBox"]) { ledger in
            var payee = try ledger.payee("StreamBox")
            payee.isArchived = true
            try ledger.save(payee)
        },
        Case(name: "StreamBox archived, then unarchived", kept: ["StreamBox"]) { ledger in
            var payee = try ledger.payee("StreamBox")
            payee.isArchived = true
            try ledger.save(payee)
            payee = try ledger.payee("StreamBox")
            payee.isArchived = false
            try ledger.save(payee)
        },
        Case(name: "Lantern given to my own transaction, then taken off", kept: ["Lantern Tea House"]) { ledger in
            var mine = Transaction(
                type: .expense,
                amount: 80,
                timeZoneID: zone.identifier,
                accountID: ledger.account.id,
            )
            mine.payeeID = try ledger.payee("Lantern Tea House").id
            try ledger.repository.saveTransaction(mine)
            var stored = try XCTUnwrap(try ledger.repository.transactions().first { $0.id == mine.id })
            stored.payeeID = nil
            try ledger.repository.saveTransaction(stored)
        },
        Case(name: "Lantern Tea House used by my own transaction", kept: ["Lantern Tea House"]) { ledger in
            var mine = Transaction(
                type: .expense,
                amount: 80,
                timeZoneID: zone.identifier,
                accountID: ledger.account.id,
            )
            mine.payeeID = try ledger.payee("Lantern Tea House").id
            try ledger.repository.saveTransaction(mine)
        },
        Case(name: "Lantern Tea House used by a scheduled item", kept: ["Lantern Tea House"]) { ledger in
            let day = CalendarDay(year: 2026, month: 11, day: 1)
            let now = Date(timeIntervalSince1970: 1_792_000_000)
            try ledger.repository.saveScheduledItem(
                ScheduledItem(
                    type: .expense,
                    amount: 320,
                    accountID: ledger.account.id,
                    payeeID: try ledger.payee("Lantern Tea House").id,
                    details: "Tea",
                    startDay: day,
                    timeZoneID: zone.identifier,
                    createdAt: now,
                ),
                today: day,
                now: now,
            )
        },
        Case(name: "each created payee twice in the receipt", kept: ["Bakery Two"]) { ledger in
            ledger.receipt.createdPayees += ledger.receipt.createdPayees
            var payee = try ledger.payee("Corner Bakery")
            payee.name = "Bakery Two"
            try ledger.save(payee)
        },
    ]
}

/// D384 (#254): Undo Import keeps a payee it created that was touched since (D362): renamed, given or changed a
/// default category, archived or unarchived, or given to a transaction outside the import or a scheduled item,
/// even if taken off again. It keeps payees that were there before the import, removes the untouched ones once
/// each, and undoes the rest of the import exactly. Shared by the in-memory and SwiftData stores.
@MainActor
func assertImportUndoKeepsTouchedPayees(make: MakeScheduleRepository) throws {
    typealias Fix = TouchedPayeeFixture
    for test in Fix.cases {
        var ledger = try Fix.ledger(make)
        XCTAssertEqual(
            Set(ledger.receipt.createdPayees.map(\.name)),
            ["Corner Bakery", "StreamBox", "Lantern Tea House"],
            test.name,
        )
        try test.touch(&ledger)
        let createdIDs = Set(ledger.receipt.createdPayees.map(\.id))
        let beforeUndo = try ledger.repository.ledgerSnapshot()
        let keptBefore = Set(beforeUndo.payees.filter { createdIDs.contains($0.id) && test.kept.contains($0.name) })
        XCTAssertEqual(Set(keptBefore.map(\.name)), test.kept, test.name)

        try ImportUseCases(repository: ledger.repository).ledger.undo(ledger.receipt)

        let undone = try ledger.repository.ledgerSnapshot()
        let imported = Set(ledger.receipt.transactions.map(\.id))
        XCTAssertTrue(undone.transactions.allSatisfy { !imported.contains($0.id) }, test.name)
        let created = Set(undone.payees.filter { createdIDs.contains($0.id) })
        XCTAssertEqual(created, keptBefore, "\(test.name): kept payees stay exactly as they were")
        let others = Set(undone.payees.filter { !createdIDs.contains($0.id) })
        XCTAssertEqual(
            others,
            Set(beforeUndo.payees.filter { !createdIDs.contains($0.id) }),
            "\(test.name): City Gym, from before the import, stays",
        )
        XCTAssertEqual(Set(others.map(\.id)), Set(ledger.before.payees.map(\.id)), test.name)
        XCTAssertEqual(Set(undone.accounts), Set(ledger.before.accounts), test.name)
        XCTAssertEqual(Set(undone.categories), Set(ledger.before.categories), test.name)
        let beforeIDs = Set(ledger.before.transactions.map(\.id))
        XCTAssertEqual(
            Set(undone.transactions.filter { beforeIDs.contains($0.id) }),
            Set(ledger.before.transactions),
            "\(test.name): my own transaction from before is unchanged",
        )
        XCTAssertEqual(Set(undone.scheduledItems), Set(beforeUndo.scheduledItems), test.name)
    }
}
