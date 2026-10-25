import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence

/// Made-up budgets for the #25 list tests, on top of `TransactionFeatureFixture` (today is 20 Oct 2026 in
/// Asia/Kolkata, with INR and USD accounts).
@MainActor
enum BudgetFeatureFixture {
    typealias T = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let eatingOutID = UUID(uuidString: "B6000000-0000-4000-8000-000000000001")!
    static let shoppingID = UUID(uuidString: "B6000000-0000-4000-8000-000000000002")!

    static var categories: [TransactionCategory] {
        [
            TransactionCategory(id: eatingOutID, name: "Eating out", kind: .expense, sortOrder: 90),
            TransactionCategory(id: shoppingID, name: "Shopping trips", kind: .expense, sortOrder: 91),
        ]
    }

    static func repository(
        _ budgets: [Budget] = [],
        _ transactions: [Transaction] = [],
    ) throws -> InMemoryLedgerRepository {
        let repository = try T.repository()
        for category in categories {
            try repository.saveCategory(category)
        }
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        for budget in budgets {
            try repository.saveBudget(budget)
        }
        return repository
    }

    static func budget(
        _ name: String,
        limit: Decimal,
        categories: [UUID] = [eatingOutID],
        from start: CalendarDay = CalendarDay(year: 2026, month: 10, day: 1),
        recurrence: BudgetRecurrence = .monthly,
        currency: String = "INR",
        carriesOverOverspending: Bool = false,
    ) -> Budget {
        Budget(
            name: name,
            currencyCode: currency,
            categoryIDs: categories,
            startDay: start,
            recurrence: recurrence,
            limit: limit,
            carriesOverOverspending: carriesOverOverspending,
            createdAt: T.date(2026, 9, 1),
        )
    }

    static func expense(
        _ amount: Decimal,
        in category: UUID = eatingOutID,
        month: Int = 10,
        day: Int = 10,
    ) -> Transaction {
        T.expense(amount, on: T.date(2026, month, day), category: category)
    }

    static func feature(
        _ repository: InMemoryLedgerRepository,
        updates: LedgerUpdates? = nil,
    ) -> BudgetsFeature {
        BudgetsFeature(
            useCases: BudgetScreenUseCases(list: DefaultBudgetUseCases(repository: repository, now: { T.now })),
            updates: updates,
            locale: T.india,
            today: { T.today },
        )
    }
}

/// A budget list that can't be read.
@MainActor
final class UnreadableBudgets: ListBudgetsUseCase {
    struct Unreadable: Error {}

    func budgets(today _: CalendarDay) throws -> [BudgetSummary] {
        throw Unreadable()
    }

    func overspentCount(today _: CalendarDay) throws -> Int {
        throw Unreadable()
    }
}
