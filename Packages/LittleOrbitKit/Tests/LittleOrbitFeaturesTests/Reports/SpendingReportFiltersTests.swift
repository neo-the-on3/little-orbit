import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Periods, the account filter and Try Again on the spending report (#184). Made-up data only.
@MainActor
@Suite("Spending report filters and Try Again (#184)")
struct SpendingReportFiltersTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    static let rewards = Account(name: "Rewards Card", type: .creditCard, currencyCode: "INR")
    static let vault = Account(name: "Quiet Vault", type: .savings, currencyCode: "INR", isHidden: true)
    static let eurWallet = Account(name: "EUR Wallet", type: .checking, currencyCode: "EUR")

    /// ICU puts thin or narrow no-break spaces around an interval's dash on some platforms.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2009}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    static func snapshot(_ transactions: [Transaction]) -> LedgerSnapshot {
        var snapshot = S.snapshot(transactions)
        snapshot.accounts += [rewards, vault, eurWallet]
        return snapshot
    }

    @Test("Given October 2026, This Quarter is Oct – Dec 2026 and Last Quarter is Jul – Sep 2026")
    func quarters() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([S.expense("100", S.rent, 10, 1), S.expense("200", S.rent, 8, 15)])
        )
        let model = S.model(fake)
        await model.load()
        await model.select(.thisQuarter)
        #expect(Self.plain(model.periodTitle) == "Oct – Dec 2026")
        #expect(model.totalText == "₹100.00")
        #expect(
            fake.requests.last?.range
                == .init(start: .init(year: 2026, month: 10, day: 1), end: .init(year: 2026, month: 12, day: 31))
        )
        await model.select(.lastQuarter)
        #expect(Self.plain(model.periodTitle).hasPrefix("Jul – Sep"))
        #expect(Self.plain(model.periodTitle).hasSuffix(" 2026"))
        #expect(model.totalText == "₹200.00")
    }

    @Test("Given October 2026, › shows November 2026 and ‹ goes back to October 2026")
    func stepping() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([S.expense("100", S.rent, 10, 1), S.expense("300", S.rent, 11, 2)])
        )
        let model = S.model(fake)
        await model.load()
        #expect(!model.isStepped)
        #expect(model.canStep)
        await model.step(by: 1)
        #expect(model.periodTitle == "November 2026")
        #expect(model.totalText == "₹300.00")
        #expect(model.period == .thisMonth)
        #expect(model.isStepped)
        await model.step(by: -1)
        #expect(model.periodTitle == "October 2026")
        #expect(model.totalText == "₹100.00")
        #expect(!model.isStepped)
        #expect(model.previousPeriodLabel == "Previous Period")
        #expect(model.nextPeriodLabel == "Next Period")
    }

    @Test("Given I tap › from October 2026, when I pick This Month, then the report shows October 2026 again")
    func presetAfterStep() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([S.expense("100", S.rent, 10, 1), S.expense("300", S.rent, 11, 2)])
        )
        let model = S.model(fake)
        await model.load()
        await model.step(by: 1)
        #expect(model.isStepped)
        await model.select(.thisMonth)
        #expect(!model.isStepped)
        #expect(model.periodTitle == "October 2026")
        #expect(model.totalText == "₹100.00")
        #expect(fake.requests.last?.range.start == .init(year: 2026, month: 10, day: 1))
    }

    @Test("Given ₹100.00 on 15 Sep and ₹200.00 on 14 Oct 2026, a custom 15 Sep–14 Oct range totals ₹300.00")
    func customRange() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                S.expense("50", S.rent, 9, 14),
                S.expense("100", S.rent, 9, 15),
                S.expense("200", S.rent, 10, 14),
                S.expense("70", S.rent, 10, 15),
            ])
        )
        let model = S.model(fake)
        await model.load()
        await model.selectCustomRange()
        #expect(model.isCustomRange)
        #expect(model.period == nil)
        #expect(model.periodTitle == "October 2026")
        await model.selectCustomRange(from: S.date(9, 15), to: S.date(10, 14))
        #expect(model.totalText == "₹300.00")
        // “15 Sep – 14 Oct 2026”; ICU versions spell September “Sep” or “Sept”.
        #expect(Self.plain(model.periodTitle).hasPrefix("15 Sep"))
        #expect(Self.plain(model.periodTitle).hasSuffix(" – 14 Oct 2026"))
        #expect(model.periodTitle.components(separatedBy: "2026").count == 2)
        // ‹ › are disabled for a custom range, and stepping does nothing.
        #expect(!model.canStep)
        #expect(!model.isStepped)
        let requests = fake.requests.count
        await model.step(by: 1)
        #expect(fake.requests.count == requests)
        #expect(model.totalText == "₹300.00")
        // An end before the start is read start first.
        await model.selectCustomRange(from: S.date(10, 14), to: S.date(9, 15))
        #expect(model.totalText == "₹300.00")
        #expect(model.customRangeName == "Custom…")
        #expect(model.bothDatesIncluded == "Both dates are included.")
    }

    @Test("The filter lists only the shown currency's accounts, hidden ones too, all ticked: “· all accounts”")
    func accountList() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                S.expense("1000", S.rent, 10, 1),
                S.expense("40", S.rent, 10, 1, account: Self.eurWallet),
            ])
        )
        let model = S.model(fake)
        await model.load()
        #expect(model.accounts.map(\.account.name) == ["Everyday Savings", "Quiet Vault", "Rewards Card"])
        #expect(model.accounts.allSatisfy { $0.isIncluded })
        #expect(model.totalCaption == "Spent in October 2026 · all accounts · INR")
        #expect(model.accountsValue == "All")
        #expect(model.accountsFooter == "Only INR accounts are listed because the report shows INR.")
        #expect(model.accountsTitle == "Accounts")
        #expect(model.hiddenAccountNote == "Hidden")
    }

    @Test("Given a hidden account with ₹500.00 spent, it counts until it's unticked, then the ₹500.00 is gone (D417)")
    func hiddenAccount() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                S.expense("1000", S.rent, 10, 1),
                S.expense("500", S.groceries, 10, 2, account: Self.vault),
            ])
        )
        let model = S.model(fake)
        await model.load()
        #expect(model.totalText == "₹1,500.00")
        await model.setAccount(Self.vault.id, included: false)
        #expect(model.totalText == "₹1,000.00")
        #expect(model.rows.map(\.name) == ["Rent"])
        #expect(model.totalCaption == "Spent in October 2026 · 2 of 3 accounts · INR")
        #expect(model.accountsValue == "2 of 3")
        await model.setAccount(Self.vault.id, included: true)
        #expect(model.totalText == "₹1,500.00")
        #expect(model.totalCaption == "Spent in October 2026 · all accounts · INR")
    }

    @Test("Given I untick Rewards Card, the totals and drill-downs count only the ticked accounts")
    func untickedAccount() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                S.expense("1000", S.rent, 10, 1),
                S.expense("250", S.rent, 10, 3, account: Self.rewards),
            ])
        )
        let model = S.model(fake)
        await model.load()
        await model.setAccount(Self.rewards.id, included: false)
        await model.setAccount(Self.vault.id, included: false)
        #expect(model.totalText == "₹1,000.00")
        // Never the one ticked account's name: “1 of 3 accounts”.
        #expect(model.totalCaption == "Spent in October 2026 · 1 of 3 accounts · INR")
        let row = try #require(model.rows.first)
        let drill = try #require(await model.drillDown(for: row))
        #expect(drill.caption == "\(try #require(row.shareText)) of spending · October 2026 · 1 of 3 accounts · INR")
        #expect(drill.amountText == "₹1,000.00")
        #expect(drill.entries.count == 1)
        #expect(fake.entryRequests.last?.accounts.unticked == [Self.rewards.id, Self.vault.id])
    }

    @Test("Given one ticked account, when I untick it, then it stays ticked and the report is unchanged (B1 on #307)")
    func lastTickedAccount() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                S.expense("1000", S.rent, 10, 1),
                S.expense("250", S.rent, 10, 3, account: Self.rewards),
            ])
        )
        let model = S.model(fake)
        await model.load()
        #expect(model.canUntick(S.savings.id))
        await model.setAccount(Self.rewards.id, included: false)
        await model.setAccount(Self.vault.id, included: false)
        #expect(!model.canUntick(S.savings.id))
        #expect(model.canUntick(Self.rewards.id))
        let requests = fake.requests.count
        await model.setAccount(S.savings.id, included: false)
        #expect(fake.requests.count == requests)
        #expect(model.accounts.filter { $0.isIncluded }.map(\.id) == [S.savings.id])
        #expect(model.totalText == "₹1,000.00")
        #expect(!model.rows.isEmpty)
        #expect(model.totalCaption == "Spent in October 2026 · 1 of 3 accounts · INR")
    }

    @Test("Given an unticked INR account, when I switch to EUR and back, then every account is ticked again")
    func currencyResetsAccounts() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                S.expense("1000", S.rent, 10, 1),
                S.expense("40", S.rent, 10, 1, account: Self.eurWallet),
            ])
        )
        let model = S.model(fake)
        await model.load()
        await model.setAccount(Self.rewards.id, included: false)
        #expect(model.accountsValue == "2 of 3")
        await model.selectCurrency("EUR")
        #expect(model.accounts.map(\.account.name) == ["EUR Wallet"])
        #expect(model.totalCaption == "Spent in October 2026 · all accounts · EUR")
        await model.selectCurrency("INR")
        #expect(model.accounts.allSatisfy { $0.isIncluded })
        #expect(model.totalCaption == "Spent in October 2026 · all accounts · INR")
    }

    @Test("Given the report fails to load, when I tap Try Again and the read succeeds, then the report shows")
    func retry() async {
        let fake = FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("100", S.rent, 10, 1)]))
        fake.fails = true
        let model = S.model(fake)
        await model.load()
        #expect(model.loadFailed)
        #expect(model.tryAgainButton == "Try Again")
        fake.fails = false
        await model.retry()
        #expect(!model.loadFailed)
        #expect(model.totalText == "₹100.00")
    }

    @Test("Given an open drill-down that failed, when I tap Try Again, then the report and the drill-down both reload")
    func drillDownRetry() async throws {
        let fake = FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("100", S.rent, 10, 1)]))
        let model = S.model(fake)
        await model.load()
        let drill = model.makeDrillDown(for: try #require(model.rows.first))
        fake.fails = true
        await drill.load()
        #expect(drill.loadFailed)
        fake.fails = false
        fake.snapshot.transactions.append(S.expense("50", S.rent, 10, 2))
        await drill.retry()
        #expect(!drill.loadFailed)
        #expect(drill.drillDown?.amountText == "₹150.00")
        #expect(model.totalText == "₹150.00")
    }
}
