import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Accounts home")
struct AccountsViewModelTests {
    private func model(
        _ repository: InMemoryLedgerRepository,
        planned: PlannedItemCounts = PlannedItemCounts(),
        budgetsEnabled: Bool = FeatureFlags.budgetsEnabled,
    ) -> AccountsViewModel {
        let model = AccountsViewModel(
            useCases: FeatureFixture.useCases(repository),
            plannedItems: StubPlannedItems(planned),
            budgetsEnabled: budgetsEnabled,
            locale: FeatureFixture.india,
        )
        model.load()
        return model
    }

    @Test("First run: no accounts, empty home rows, net wealth placeholder (S79, S85)")
    func firstRun() throws {
        let model = model(try FeatureFixture.repository([]))
        #expect(model.isFirstRun)
        #expect(model.assets.isEmpty && model.credit.isEmpty)
        #expect(model.netWealth.isEmpty)
        #expect(model.netWealthSummary == "—")
        #expect(model.homeRows.map(\.title) == ["Scheduled", "Reports"])
        #expect(model.homeRows.map(\.subtitle) == ["Nothing scheduled", "No transactions yet"])
        #expect(model.homeRows.allSatisfy { $0.badge == nil })
    }

    @Test("First account flow: Everyday Savings ₹25,000.00 shows in the list and net wealth (S1)")
    func firstAccount() throws {
        let repository = try FeatureFixture.repository([])
        let model = model(repository)
        try repository.saveAccount(
            Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", openingBalance: 25_000)
        )
        model.load()
        #expect(!model.isFirstRun)
        #expect(model.assets.map(\.name) == ["Everyday Savings"])
        #expect(model.assets.first?.balanceText == "₹25,000.00")
        #expect(model.netWealthSummary == "₹25,000.00")
    }

    @Test("Fixture: sections, hidden count and per-currency net wealth (S23, S48, S49)")
    func fixture() throws {
        let model = model(try FeatureFixture.repository())
        #expect(model.assets.map(\.name) == ["Everyday Savings", "Corner Wallet", "Holiday Fund", "Euro Pocket"])
        #expect(model.credit.map(\.name) == ["Travel Card"])
        #expect(model.hiddenCount == 2)
        #expect(model.showHiddenTitle == "Show hidden accounts (2)")
        #expect(model.netWealth.map(\.text) == ["₹16,650.50", "€300.00", "$1,240.00"])
        #expect(model.netWealthSummary == "₹16,650.50 · €300.00 · $1,240.00")
        #expect(model.allAccountsAccessibilityLabel == "All Accounts, net wealth ₹16,650.50 · €300.00 · $1,240.00")
    }

    @Test("Credit row: balance first, available credit second (S2, D52)")
    func creditRow() throws {
        let model = model(try FeatureFixture.repository())
        let card = try #require(model.credit.first)
        #expect(card.balanceText == "−₹30,000.00")
        #expect(card.balanceTone == .negative)
        // In the Credit section the type prefix is dropped; elsewhere it stays (UI Designer, #82 U1).
        #expect(
            card.subtitle(inTypeSection: true)
                == AccountSubtitle(text: "₹70,000.00 available", isWarning: false, figure: "₹70,000.00")
        )
        #expect(card.subtitle(inTypeSection: false).text == "Credit card · ₹70,000.00 available")
        // The figure is its own unit so a narrow row breaks around it, never inside it (D169, #82 B10).
        #expect(
            card.subtitle(inTypeSection: true).figureParts
                == AccountSubtitle.FigureParts(before: "", figure: "₹70,000.00", after: "available")
        )
        #expect(
            card.subtitle(inTypeSection: false).figureParts
                == AccountSubtitle.FigureParts(before: "Credit card ·", figure: "₹70,000.00", after: "available")
        )
        #expect(card.warning == nil)
        #expect(card.detailCaption == "Credit card · INR · Available credit ₹70,000.00 of ₹1,00,000.00")
        // VoiceOver says what the row shows, with the figure spelled out (UI Designer, #82 B4/U5).
        #expect(card.accessibilityLabel == "Travel Card, −₹30,000.00, Available credit ₹70,000.00")
    }

    @Test("Over the limit reads Available credit ₹0.00 and a red over-limit line (S78)")
    func overLimit() throws {
        let card = Account(
            name: "Travel Card",
            type: .creditCard,
            currencyCode: "INR",
            openingBalance: -105_000,
            creditLimit: 100_000,
            showAvailableCredit: true,
        )
        let row = try #require(model(try FeatureFixture.repository([card])).credit.first)
        // In section: only the over-limit text, in the destructive colour (UI Designer, #82 U1).
        #expect(
            row.subtitle(inTypeSection: true)
                == AccountSubtitle(text: "Over limit by ₹5,000.00", isWarning: true, figure: "₹5,000.00")
        )
        #expect(
            row.subtitle(inTypeSection: false)
                == AccountSubtitle(text: "Credit card · Over limit by ₹5,000.00", isWarning: true, figure: "₹5,000.00")
        )
        #expect(
            row.subtitle(inTypeSection: true).figureParts
                == AccountSubtitle.FigureParts(before: "Over limit by", figure: "₹5,000.00", after: "")
        )
        #expect(row.warning == "Over limit by ₹5,000.00")
        // The over-limit line shows once, as the red line under the header balance (Tester bug 3).
        #expect(row.detailCaption == "Credit card · INR · Available credit ₹0.00")
        // VoiceOver matches the row: the over-limit line only, never "Available credit ₹0.00" (#82 U5).
        #expect(row.accessibilityLabel == "Travel Card, −₹1,05,000.00, Over limit by ₹5,000.00")
    }

    @Test("In credit shows a plus balance and more available than the limit (S78a, S90)")
    func inCredit() throws {
        let card = Account(
            name: "Weekend Card",
            type: .creditCard,
            currencyCode: "INR",
            openingBalance: 2_000,
            creditLimit: 50_000,
            showAvailableCredit: true,
        )
        let row = try #require(model(try FeatureFixture.repository([card])).credit.first)
        #expect(row.balanceText == "+₹2,000.00")
        #expect(row.balanceTone == .positive)
        #expect(row.subtitle(inTypeSection: true).text == "₹52,000.00 available")
        #expect(row.subtitle(inTypeSection: false).text == "Credit card · ₹52,000.00 available")
        #expect(row.detailCaption == "Credit card · INR · Available credit ₹52,000.00 of ₹50,000.00")
    }

    @Test("No limit and loans show only type and currency (S74, S81, S89)")
    func noAvailableLine() throws {
        let noLimit = Account(
            name: "Rewards Card",
            type: .creditCard,
            currencyCode: "INR",
            openingBalance: -30_000,
            sortOrder: 1,
        )
        let loan = Account(
            name: "Home Loan",
            type: .loan,
            currencyCode: "INR",
            openingBalance: -800_000,
            sortOrder: 2,
            creditLimit: 900_000,
        )
        let rows = model(try FeatureFixture.repository([noLimit, loan])).credit
        // Without an available-credit figure the type stays, so the line never reads just "INR".
        #expect(rows.map { $0.subtitle(inTypeSection: true).text } == ["Credit card · INR", "Loan · INR"])
        #expect(rows.map { $0.subtitle(inTypeSection: false).text } == ["Credit card · INR", "Loan · INR"])
        #expect(rows.allSatisfy { !$0.subtitle(inTypeSection: true).isWarning })
        // No figure, so nothing to keep whole: the line wraps as plain text (D169).
        #expect(rows.allSatisfy { $0.subtitle(inTypeSection: true).figureParts == nil })
        #expect(rows.allSatisfy { $0.warning == nil })
    }

    @Test("Show hidden lists hidden accounts with a Hidden tag and keeps net wealth (S68, S69)")
    func showHidden() throws {
        let model = model(try FeatureFixture.repository())
        let before = model.netWealthSummary
        model.showHidden = true
        #expect(
            model.assets.map(\.name) == [
                "Everyday Savings", "Corner Wallet", "Long Term Fund", "Old Locker", "Holiday Fund", "Euro Pocket",
            ]
        )
        let fund = try #require(model.assets.first { $0.name == "Long Term Fund" })
        #expect(fund.isHidden)
        #expect(fund.balanceText == "₹20,000.00")
        #expect(fund.sidebarTitle == "Long Term Fund · Hidden")
        #expect(fund.accessibilityLabel.contains("Hidden"))
        let locker = try #require(model.assets.first { $0.name == "Old Locker" })
        #expect(locker.isHidden && locker.isExcluded)
        #expect(model.netWealthSummary == before)
    }

    @Test("Hide and unhide apply at once and never change net wealth (S70, S72)")
    func hideAndUnhide() throws {
        let model = model(try FeatureFixture.repository())
        let wallet = try #require(model.assets.first { $0.name == "Corner Wallet" })
        let before = model.netWealthSummary
        model.setHidden(true, accountID: wallet.id)
        #expect(!model.assets.contains { $0.id == wallet.id })
        #expect(model.hiddenCount == 3)
        #expect(model.netWealthSummary == before)
        model.showHidden = true
        model.setHidden(false, accountID: wallet.id)
        model.showHidden = false
        #expect(model.assets.contains { $0.id == wallet.id })
    }

    @Test("Unhiding a hidden and excluded account keeps it excluded (S71)")
    func unhideKeepsExclusion() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        let locker = try #require(try repository.accounts().first { $0.name == "Old Locker" })
        model.setHidden(false, accountID: locker.id)
        let row = try #require(model.assets.first { $0.id == locker.id })
        #expect(row.isExcluded)
        #expect(model.netWealthSummary == "₹16,650.50 · €300.00 · $1,240.00")
    }

    @Test("Excluding Holiday Fund drops the USD line (S50, S52)")
    func exclude() throws {
        let model = model(try FeatureFixture.repository())
        let holiday = try #require(model.assets.first { $0.name == "Holiday Fund" })
        model.setExcluded(true, accountID: holiday.id)
        #expect(model.netWealthSummary == "₹16,650.50 · €300.00")
        #expect(model.assets.first { $0.id == holiday.id }?.isExcluded == true)
    }

    @Test("Reordering within a section sticks across a reload (S3, S38)")
    func reorder() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        model.move(in: .assets, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(model.assets.map(\.name) == ["Euro Pocket", "Everyday Savings", "Corner Wallet", "Holiday Fund"])
        let relaunched = self.model(repository)
        #expect(relaunched.assets.map(\.name) == ["Euro Pocket", "Everyday Savings", "Corner Wallet", "Holiday Fund"])
    }

    @Test("Reordering with hidden accounts shown keeps them in place (D109)")
    func reorderWithHiddenShown() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        model.showHidden = true
        model.move(in: .assets, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(
            model.assets.map(\.name) == [
                "Corner Wallet", "Long Term Fund", "Everyday Savings", "Old Locker", "Holiday Fund", "Euro Pocket",
            ]
        )
    }

    @Test("Renumbering with hidden accounts off still keeps them in place when shown (D109)")
    func renumberKeepsHiddenInPlace() throws {
        var tick = 0.0
        let repository = InMemoryLedgerRepository {
            tick += 1
            return Date(timeIntervalSince1970: tick)
        }
        for (name, hidden) in [("A", false), ("Hidden", true), ("B", false), ("C", false)] {
            try repository.saveAccount(
                Account(name: name, type: .savings, currencyCode: "INR", isHidden: hidden, sortOrder: 0)
            )
        }
        let model = model(repository)
        #expect(model.assets.map(\.name) == ["A", "B", "C"])
        model.move(in: .assets, fromOffsets: IndexSet(integer: 2), toOffset: 1)
        #expect(model.assets.map(\.name) == ["A", "C", "B"])
        model.showHidden = true
        #expect(model.assets.map(\.name) == ["A", "Hidden", "C", "B"])
        #expect(Set(try repository.accounts().map(\.sortOrder)).count == 4)
    }

    @Test("Reorder mode only reorders: hide, exclude and delete do nothing until Done (D151)")
    func reorderModeOnlyReorders() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        let confirmation = AccountDeleteConfirmation(model: model)
        #expect(!model.isReordering)
        #expect(model.allowsRowActions)
        model.isReordering = true
        #expect(!model.allowsRowActions)
        let id = try #require(model.assets.first?.id)
        model.setHidden(true, accountID: id)
        model.setExcluded(true, accountID: id)
        confirmation.request(accountID: id)
        #expect(confirmation.prompt == nil)
        #expect(try repository.accounts().first { $0.id == id }?.isHidden == false)
        #expect(try repository.accounts().first { $0.id == id }?.includeInNetWorth == true)
        model.move(in: .assets, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(model.assets.first?.name == "Euro Pocket")
        model.isReordering = false
        #expect(model.allowsRowActions)
        model.setHidden(true, accountID: id)
        #expect(try repository.accounts().first { $0.id == id }?.isHidden == true)
    }

    @Test("Delete asks first with counts and transfers, and Hide is offered (S10, D19)")
    func deletePrompt() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        let confirmation = AccountDeleteConfirmation(model: model)
        let accounts = try repository.accounts()
        let savings = try #require(accounts.first { $0.name == "Everyday Savings" })
        let wallet = try #require(accounts.first { $0.name == "Corner Wallet" })
        for _ in 0..<117 {
            try repository.saveTransaction(Transaction(type: .expense, amount: 10, accountID: savings.id))
        }
        for _ in 0..<3 {
            try repository.saveTransaction(
                Transaction(type: .transfer, amount: 100, accountID: savings.id, transferAccountID: wallet.id)
            )
        }
        model.load()
        confirmation.request(accountID: savings.id)
        let prompt = try #require(confirmation.prompt)
        #expect(prompt.title == "Delete “Everyday Savings”?")
        #expect(
            prompt.message
                == "This deletes 120 transactions, including 3 transfers to or from other accounts whose balances will change. Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth."
        )
        #expect(prompt.hideTitle == "Hide Account")
        #expect(prompt.deleteTitle == "Delete Account")
        #expect(try repository.accounts().count == 7)
    }

    @Test("Cancel deletes nothing (S11)")
    func cancel() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        let confirmation = AccountDeleteConfirmation(model: model)
        let id = try #require(model.assets.first?.id)
        confirmation.request(accountID: id)
        confirmation.cancel()
        #expect(confirmation.prompt == nil)
        #expect(try repository.accounts().count == 7)
    }

    @Test("Hide Account hides instead of deleting (S12)")
    func hideInstead() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        let confirmation = AccountDeleteConfirmation(model: model)
        let id = try #require(model.assets.first?.id)
        let before = model.netWealthSummary
        confirmation.request(accountID: id)
        confirmation.hide()
        #expect(confirmation.prompt == nil)
        #expect(try repository.accounts().count == 7)
        #expect(try repository.accounts().first { $0.id == id }?.isHidden == true)
        #expect(model.netWealthSummary == before)
    }

    @Test("Confirming deletes the account and its transfers; the other balance moves back (S13, S15)")
    func confirm() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        let confirmation = AccountDeleteConfirmation(model: model)
        let accounts = try repository.accounts()
        let savings = try #require(accounts.first { $0.name == "Everyday Savings" })
        let holiday = try #require(accounts.first { $0.name == "Holiday Fund" })
        try repository.saveTransaction(
            Transaction(
                type: .transfer,
                amount: 1_000,
                accountID: savings.id,
                transferAccountID: holiday.id,
                destinationAmount: 12,
            )
        )
        model.load()
        #expect(model.assets.first?.balanceText == "₹24,000.00")
        confirmation.request(accountID: holiday.id)
        #expect(
            confirmation.prompt?.message
                == "This deletes 1 transaction, a transfer to or from another account whose balance will change. Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth."
        )
        confirmation.confirm()
        #expect(!model.assets.contains { $0.id == holiday.id })
        #expect(model.assets.first?.balanceText == "₹25,000.00")
        #expect(try repository.transactions().isEmpty)
    }

    @Test("An account with no transactions gives no count and still offers Hide (S16, D236)")
    func zeroTransactions() throws {
        let model = model(try FeatureFixture.repository())
        let confirmation = AccountDeleteConfirmation(model: model)
        let id = try #require(model.assets.first?.id)
        confirmation.request(accountID: id)
        #expect(
            confirmation.prompt?.message
                == "This account has no transactions. You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth."
        )
        #expect(confirmation.prompt?.hideTitle == "Hide Account")
    }

    @Test("Home badges count and cap; zero hides the badge (S57, S59, S84)")
    func homeBadges() throws {
        let model = model(
            try FeatureFixture.repository(),
            planned: PlannedItemCounts(
                budgetCount: 3,
                overspentBudgetCount: 2,
                scheduledItemCount: 5,
                overdueOccurrenceCount: 120,
            ),
            budgetsEnabled: true,
        )
        let rows = model.homeRows
        #expect(rows.map(\.badge) == ["2", "99+", nil])
        #expect(rows.map(\.subtitle) == [nil, nil, "No transactions yet"])
        #expect(rows[0].accessibilityLabel == "Budgets, 2 overspent")
        #expect(rows[1].accessibilityLabel == "Scheduled, 120 overdue")
        #expect(rows[2].accessibilityLabel == "Reports, No transactions yet")
    }

    @Test("Reports clears No transactions yet with any transaction, hidden accounts included (S99, D114)")
    func reportsSubtitle() throws {
        let repository = try FeatureFixture.repository()
        let model = model(repository)
        let hidden = try #require(try repository.accounts().first { $0.isHidden })
        try repository.saveTransaction(Transaction(type: .expense, amount: 1, accountID: hidden.id))
        model.load()
        let reports = try #require(model.homeRows.first { $0.destination == .reports })
        #expect(reports.subtitle == nil)
        #expect(reports.accessibilityLabel == "Reports")
        #expect(model.assets.first { $0.name == "Everyday Savings" }?.hasTransactions == false)
    }

    @Test("Each row announces name, balance, type and status (S35)")
    func accessibility() throws {
        let model = model(try FeatureFixture.repository())
        model.showHidden = true
        let locker = try #require(model.assets.first { $0.name == "Old Locker" })
        #expect(locker.accessibilityLabel == "Old Locker, ₹5,000.00, Other, Hidden, Excluded from net wealth")
    }
}
