#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// Budgets (#25), through the same `LedgerBook` rules as the in-memory store.
    extension SwiftDataLedgerRepository: BudgetRepository {
        public func budgets() throws -> [Budget] {
            try load().budgetsVisible()
        }

        public func saveBudget(_ budget: Budget) throws {
            let now = self.now()
            try mutate { try LedgerBook.savingBudget(budget, in: $0, now: now) }
        }

        public func restoreBudget(_ budget: Budget) throws {
            let now = self.now()
            try mutate { try LedgerBook.restoringBudget(budget, in: $0, now: now) }
        }

        public func changeBudgetLimit(
            of budgetID: UUID,
            to amount: Decimal,
            fromPeriodStartingOn periodStart: CalendarDay,
        ) throws {
            let now = self.now()
            try mutate {
                try LedgerBook.changingBudgetLimit(
                    of: budgetID,
                    to: amount,
                    fromPeriodStartingOn: periodStart,
                    in: $0,
                    now: now,
                )
            }
        }

        public func deleteBudget(id: UUID) throws {
            try mutate { try LedgerBook.deletingBudget(id: id, in: $0) }
        }

        /// Attachments come without their bytes: the list and the badge never need them (#174 review NB2).
        public func budgetLedger() throws -> LedgerSnapshot {
            try backupSnapshot()
        }

        /// Writes the snapshot's budgets and limits, links each budget to its categories and each limit to its
        /// budget, and deletes the ones that are gone. Part of the one save in `write`.
        func applyBudgets(
            _ snapshot: LedgerSnapshot,
            categories: [UUID: LittleOrbitSchemaV1.CategoryRecord],
        ) throws {
            let budgets = try fetch(LittleOrbitSchemaV1.BudgetRecord.self)
            let limits = try fetch(LittleOrbitSchemaV1.BudgetLimitRecord.self)
            var currencyOfLimit: [UUID: String] = [:]
            var budgetOfLimit: [UUID: UUID] = [:]
            for budget in snapshot.budgets {
                for limit in budget.limits {
                    currencyOfLimit[limit.id] = budget.currencyCode
                    budgetOfLimit[limit.id] = budget.id
                }
            }
            let allLimits = snapshot.budgets.flatMap(\.limits)
            let budgetRecords = try upsert(snapshot.budgets, existing: budgets) {
                LittleOrbitSchemaV1.BudgetRecord()
            } apply: { record, budget in
                record.apply(budget)
            }
            let limitRecords = try upsert(allLimits, existing: limits) {
                LittleOrbitSchemaV1.BudgetLimitRecord()
            } apply: { record, limit in
                try record.apply(limit, currencyCode: currencyOfLimit[limit.id] ?? CurrencyCode.fallback)
            }
            for record in budgetRecords.values {
                record.categories = []
            }
            for record in limitRecords.values {
                record.budget = nil
            }
            deleteMissing(limits, keeping: Set(allLimits.map(\.id)))
            deleteMissing(budgets, keeping: Set(snapshot.budgets.map(\.id)))
            for budget in snapshot.budgets {
                budgetRecords[budget.id]?.categories = budget.categoryIDs.compactMap { categories[$0] }
            }
            for limit in allLimits {
                limitRecords[limit.id]?.budget = budgetOfLimit[limit.id].flatMap { budgetRecords[$0] }
            }
        }
    }
#endif
