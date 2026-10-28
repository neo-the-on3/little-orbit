import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D423's merge gate (D423.5, D285.5, #308 check 3): hiding the Budgets entry never drops, migrates or changes
/// budget data. A made-up backup holding a budget restores, re-exports and restores again with the budget, and
/// everything else, unchanged while the flag is off.
@MainActor
@Suite("Budgets survive a backup round trip with the flag off (D423)")
struct BudgetsFlagOffBackupTests {
    private let groceries = TransactionCategory(name: "Groceries", kind: .expense)

    /// The made-up backup: one account, the Groceries category and a $400.00 monthly Groceries budget.
    private func madeUpBackup(_ harness: BackupHarness) throws -> (archive: Data, budget: Budget) {
        let budget = Budget(
            name: "Groceries",
            currencyCode: "USD",
            categoryIDs: [groceries.id],
            startDay: CalendarDay(year: 2026, month: 10, day: 1),
            recurrence: .monthly,
            limit: 400,
            createdAt: BackupHarness.morning,
        )
        var ledger = try harness.repository.ledgerSnapshot()
        ledger.categories.append(groceries)
        ledger.budgets = [budget]
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: BackupHarness.morning,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: ledger.accounts.count,
            transactionCount: ledger.transactions.count,
            attachmentCount: ledger.attachments.count,
        )
        let files = try BackupCodec(hashing: FakeBackupHashing())
            .encode(BackupContents(manifest: manifest, ledger: ledger))
        return (try harness.archiving.archive(files), budget)
    }

    private func harness() throws -> BackupHarness {
        try BackupHarness(
            repository: FeatureFixture.repository([
                Account(name: "Everyday Checking", type: .checking, currencyCode: "USD", openingBalance: 1_250)
            ])
        )
    }

    @Test("Check 3: restore, export a new backup and restore that; the Groceries budget comes back unchanged")
    func roundTrip() async throws {
        #expect(FeatureFlags.budgetsEnabled == false)
        let first = try harness()
        let (archive, budget) = try madeUpBackup(first)
        let backedUp = try await first.contents(.archive(.data(archive))).ledger

        _ = try await first.service.restore(.archive(.data(archive))) { _ in }
        #expect(try first.repository.budgets() == [budget])
        let restored = try first.repository.ledgerSnapshot()
        #expect(BackupContents.canonical(restored) == BackupContents.canonical(backedUp))

        let backup = try await first.service.backUpNow()
        let export = try await first.exportData(backup.id)
        let exported = try await first.contents(.archive(.data(export)))
        #expect(exported.manifest.sections.contains(.budgets))
        #expect(exported.ledger.budgets == [budget])

        let second = try harness()
        _ = try await second.service.restore(.archive(.data(export))) { _ in }
        let again = try #require(try second.repository.budgets().first)
        #expect(try second.repository.budgets().count == 1)
        #expect(again == budget)
        #expect(again.name == "Groceries")
        #expect(again.limits.map(\.amount) == [400])
        #expect(again.recurrence == .monthly)
        #expect(again.categoryIDs == [groceries.id])
        let final = try second.repository.ledgerSnapshot()
        #expect(BackupContents.canonical(final) == BackupContents.canonical(backedUp))
    }

    @Test("Check 3: with the restored budget in the store, no home or sidebar row shows Budgets")
    func hiddenAfterRestore() async throws {
        let harness = try harness()
        let (archive, budget) = try madeUpBackup(harness)
        _ = try await harness.service.restore(.archive(.data(archive))) { _ in }
        #expect(try harness.repository.budgets() == [budget])
        let model = AccountsViewModel(
            useCases: FeatureFixture.useCases(harness.repository),
            plannedItems: StubPlannedItems(PlannedItemCounts(budgetCount: 1)),
            locale: Locale(identifier: "en_US"),
        )
        model.load()
        #expect(model.homeRows.map(\.destination) == [.scheduled, .reports])
        #expect(try harness.repository.budgets() == [budget])
    }
}
