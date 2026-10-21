import Foundation
import LittleOrbitDomain
import Testing

/// The default account use cases over a fake repository.
@MainActor
@Suite("Account use cases")
struct AccountUseCasesTests {
    private func useCases(_ repository: FakeLedgerRepository) -> AccountUseCases {
        AccountUseCases(repository: repository, defaultCurrency: "INR")
    }

    @Test("Listing reads the store and reports whether there are transactions")
    func listing() throws {
        let repository = try FakeLedgerRepository(accounts: AccountFixture.all)
        let useCases = useCases(repository)
        let listing = try useCases.listAccounts.listAccounts(showHidden: false)
        #expect(
            listing.assets.map(\.account.name) == [
                "Everyday Savings", "Corner Wallet", "Holiday Fund", "Euro Pocket",
            ]
        )
        #expect(listing.hiddenCount == 2)
        #expect(!listing.hasAnyTransaction)

        let withSpend = try FakeLedgerRepository(
            accounts: AccountFixture.all,
            transactions: [AccountFixture.expense(500, from: AccountFixture.cornerWallet)],
        )
        #expect(try self.useCases(withSpend).listAccounts.listAccounts(showHidden: false).hasAnyTransaction)
    }

    @Test("Net wealth uses the default currency first")
    func netWealth() throws {
        let totals = try useCases(try FakeLedgerRepository(accounts: AccountFixture.all)).computeNetWealth.netWealth()
        #expect(totals.first?.currencyCode == "INR")
        #expect(Set(totals.map(\.currencyCode)) == ["INR", "USD", "EUR"])
    }

    @Test("A new account goes after every other account")
    func saveNew() throws {
        let repository = try FakeLedgerRepository(accounts: AccountFixture.all)
        let saved = try useCases(repository).saveAccount
            .save(
                AccountDraft(name: "Spare Cash", type: .cash, currencyCode: "INR", enteredAmount: 100),
                editing: nil,
            )
        #expect(saved.sortOrder == 8)
        #expect(try repository.accounts().count == AccountFixture.all.count + 1)
    }

    @Test("Saving an edit into an account that's gone throws and writes nothing")
    func saveEditMissing() throws {
        let repository = try FakeLedgerRepository(accounts: AccountFixture.all)
        let wallet = AccountFixture.cornerWallet
        try repository.deleteAccount(id: wallet.id)
        let draft = AccountDraft(name: "Renamed", type: .cash, currencyCode: "INR", enteredAmount: 1)
        #expect(throws: AccountUseCaseError.accountNotFound) {
            try useCases(repository).saveAccount.save(draft, editing: wallet.id)
        }
        #expect(throws: AccountUseCaseError.accountNotFound) {
            try useCases(repository).saveAccount.update(wallet.id) { $0.isHidden = true }
        }
        #expect(repository.savedAccountIDs.isEmpty)
        #expect(try repository.accounts().contains { $0.id == wallet.id } == false)
    }

    @Test("Saving an edit keeps the stored identity, order and creation date")
    func saveEdit() throws {
        let repository = try FakeLedgerRepository(accounts: AccountFixture.all)
        let wallet = try #require(try repository.accounts().first { $0.id == AccountFixture.cornerWallet.id })
        var draft = AccountDraft(editing: wallet)
        draft.name = "Pocket Money"
        let saved = try useCases(repository).saveAccount.save(draft, editing: wallet.id)
        #expect(saved.id == wallet.id)
        #expect(saved.sortOrder == wallet.sortOrder)
        #expect(saved.createdAt == wallet.createdAt)
        #expect(saved.name == "Pocket Money")
    }

    @Test("The form context locks the currency once the account has a transaction, and fails for a missing id")
    func formContext() throws {
        let wallet = AccountFixture.cornerWallet
        let repository = try FakeLedgerRepository(
            accounts: AccountFixture.all,
            transactions: [AccountFixture.expense(50, from: wallet)],
        )
        let load = useCases(repository).loadAccountForm
        let context = try load.formContext(editing: wallet.id, scheduledAccountIDs: [])
        #expect(context.account?.id == wallet.id)
        #expect(context.isCurrencyLocked)
        #expect(try load.formContext(editing: nil, scheduledAccountIDs: []).account == nil)
        #expect(throws: AccountUseCaseError.accountNotFound) {
            try load.formContext(editing: UUID(), scheduledAccountIDs: [])
        }
        repository.failsReads = true
        #expect(throws: FakeLedgerRepository.ReadFailure.self) {
            try load.formContext(editing: wallet.id, scheduledAccountIDs: [])
        }
    }

    @Test("Reordering the shown rows keeps hidden accounts in the section in place (D109)")
    func reorderKeepsHidden() throws {
        let names = [("A", false), ("Hidden", true), ("B", false), ("C", false)]
        let accounts = names.map { Account(name: $0.0, type: .savings, isHidden: $0.1, sortOrder: 0) }
        let repository = try FakeLedgerRepository(accounts: accounts)
        let shown = accounts.filter { !$0.isHidden }.map(\.id)
        try useCases(repository).reorderAccounts
            .move(
                in: .assets,
                shown: shown,
                fromOffsets: IndexSet(integer: 2),
                toOffset: 1,
            )
        let listing = try useCases(repository).listAccounts.listAccounts(showHidden: true)
        #expect(listing.assets.map(\.account.name) == ["A", "Hidden", "C", "B"])
    }

    @Test("Deleting reports the D19 counts first, then removes the account")
    func delete() throws {
        let wallet = AccountFixture.cornerWallet
        let repository = try FakeLedgerRepository(
            accounts: AccountFixture.all,
            transactions: [
                AccountFixture.expense(50, from: wallet),
                AccountFixture.transfer(100, from: AccountFixture.everydaySavings, to: wallet),
            ],
        )
        let delete = useCases(repository).deleteAccount
        #expect(
            try delete.deletionImpact(of: wallet.id) == AccountDeletionImpact(transactionCount: 2, transferCount: 1)
        )
        try delete.delete(wallet.id)
        #expect(try repository.accounts().contains { $0.id == wallet.id } == false)
        #expect(try repository.transactions().isEmpty)
    }
}
