import Foundation
import LittleOrbitDomain

/// Fake account use cases for the view-model tests: canned results, recorded calls and injectable errors.
@MainActor
final class FakeAccountUseCases {
    struct Failure: Error {}

    struct Move: Equatable {
        var group: AccountGroup
        var shown: [UUID]
        var fromOffsets: IndexSet
        var toOffset: Int
    }

    var listing = AccountListing()
    var listingError: (any Error)?
    var totals: [CurrencyTotal] = []
    var formContext = AccountFormContext(accounts: [])
    var formContextError: (any Error)?
    var saveError: (any Error)?
    var impact = AccountDeletionImpact(transactionCount: 0, transferCount: 0)

    private(set) var savedDrafts: [(draft: AccountDraft, accountID: UUID?)] = []
    private(set) var updatedIDs: [UUID] = []
    private(set) var deletedIDs: [UUID] = []
    private(set) var moves: [Move] = []

    var useCases: AccountUseCases {
        AccountUseCases(
            listAccounts: self,
            computeNetWealth: self,
            loadAccountForm: self,
            saveAccount: self,
            deleteAccount: self,
            reorderAccounts: self,
        )
    }

    func listAccounts(showHidden: Bool) throws -> AccountListing {
        if let listingError {
            throw listingError
        }
        return listing
    }

    func netWealth() throws -> [CurrencyTotal] { totals }

    func formContext(editing accountID: UUID?, scheduledAccountIDs: Set<UUID>) throws -> AccountFormContext {
        if let formContextError {
            throw formContextError
        }
        return formContext
    }

    func save(_ draft: AccountDraft, editing accountID: UUID?) throws -> Account {
        if let saveError {
            throw saveError
        }
        savedDrafts.append((draft, accountID))
        return draft.applied(to: Account(id: accountID ?? UUID()))
    }

    func update(_ accountID: UUID, _ change: (inout Account) -> Void) throws {
        if let saveError {
            throw saveError
        }
        updatedIDs.append(accountID)
    }

    func deletionImpact(of accountID: UUID) throws -> AccountDeletionImpact { impact }

    func delete(_ accountID: UUID) throws -> RemovedAccount {
        deletedIDs.append(accountID)
        return RemovedAccount(account: Account(id: accountID), transactions: [])
    }

    func move(in group: AccountGroup, shown: [UUID], fromOffsets: IndexSet, toOffset: Int) throws {
        moves.append(Move(group: group, shown: shown, fromOffsets: fromOffsets, toOffset: toOffset))
    }
}

extension FakeAccountUseCases: ListAccountsUseCase, ComputeNetWealthUseCase, LoadAccountFormUseCase {}
extension FakeAccountUseCases: SaveAccountUseCase, DeleteAccountUseCase, ReorderAccountsUseCase {}
