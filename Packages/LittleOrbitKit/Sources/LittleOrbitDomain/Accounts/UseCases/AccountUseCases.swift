import Foundation

// The account use cases. View models depend only on these protocols, injected through their initializers.
// The `Default…` implementations below hold the business logic and depend on `LedgerRepository`. The App target
// builds them once, over the store it opened, and wires them in (MVVM + Clean, Kiran's answer on #82).

/// Errors the account use cases add on top of the ledger's own validation errors.
public enum AccountUseCaseError: Error, Equatable, Sendable {
    /// The account isn't in the store: it was never there, or it was deleted, for example while an edit form
    /// was open. An edit never saves a new account in its place.
    case accountNotFound
}

/// The account list for the iOS home and the macOS sidebar.
@MainActor
public protocol ListAccountsUseCase {
    func listAccounts(showHidden: Bool) throws -> AccountListing
}

/// Net wealth, one total per currency.
@MainActor
public protocol ComputeNetWealthUseCase {
    func netWealth() throws -> [CurrencyTotal]
}

/// What the account form needs before it opens.
public struct AccountFormContext: Equatable, Sendable {
    /// Every live account, for the duplicate-name hint.
    public var accounts: [Account]
    /// The account being edited, or `nil` for a new one.
    public var account: Account?
    public var isCurrencyLocked: Bool

    public init(accounts: [Account], account: Account? = nil, isCurrencyLocked: Bool = false) {
        self.accounts = accounts
        self.account = account
        self.isCurrencyLocked = isCurrencyLocked
    }
}

@MainActor
public protocol LoadAccountFormUseCase {
    /// Throws `AccountUseCaseError.accountNotFound` when `accountID` isn't in the store.
    func formContext(editing accountID: UUID?, scheduledAccountIDs: Set<UUID>) throws -> AccountFormContext
}

@MainActor
public protocol SaveAccountUseCase {
    /// Saves the form's values as a new account (`accountID == nil`, placed after every other account) or into
    /// the existing account. Throws `AccountUseCaseError.accountNotFound` if that account is gone.
    func save(_ draft: AccountDraft, editing accountID: UUID?) throws -> Account
    /// Changes one stored account, such as hiding or excluding it. Throws `accountNotFound` if it's gone.
    func update(_ accountID: UUID, _ change: (inout Account) -> Void) throws
}

@MainActor
public protocol DeleteAccountUseCase {
    /// The transactions and transfers a delete would remove (D19).
    func deletionImpact(of accountID: UUID) throws -> AccountDeletionImpact
    /// Deletes the account with its transactions, transfers in or out, and their attachments (D19).
    func delete(_ accountID: UUID) throws
}

@MainActor
public protocol ReorderAccountsUseCase {
    /// Moves accounts within one section. `shown` is the section as the list shows it, which can leave hidden
    /// accounts out; the offsets are the ones SwiftUI's `onMove` passes. Hidden accounts keep their place (D109).
    func move(in group: AccountGroup, shown: [UUID], fromOffsets: IndexSet, toOffset: Int) throws
}

/// The account use cases as one value, so the composition root can hand them to a feature in one go.
@MainActor
public struct AccountUseCases {
    public var listAccounts: any ListAccountsUseCase
    public var computeNetWealth: any ComputeNetWealthUseCase
    public var loadAccountForm: any LoadAccountFormUseCase
    public var saveAccount: any SaveAccountUseCase
    public var deleteAccount: any DeleteAccountUseCase
    public var reorderAccounts: any ReorderAccountsUseCase

    public init(
        listAccounts: any ListAccountsUseCase,
        computeNetWealth: any ComputeNetWealthUseCase,
        loadAccountForm: any LoadAccountFormUseCase,
        saveAccount: any SaveAccountUseCase,
        deleteAccount: any DeleteAccountUseCase,
        reorderAccounts: any ReorderAccountsUseCase,
    ) {
        self.listAccounts = listAccounts
        self.computeNetWealth = computeNetWealth
        self.loadAccountForm = loadAccountForm
        self.saveAccount = saveAccount
        self.deleteAccount = deleteAccount
        self.reorderAccounts = reorderAccounts
    }

    /// The default implementations over one repository.
    public init(repository: any LedgerRepository, defaultCurrency: String = CurrencyCode.deviceDefault) {
        self.init(
            listAccounts: DefaultListAccountsUseCase(repository: repository),
            computeNetWealth: DefaultComputeNetWealthUseCase(repository: repository, defaultCurrency: defaultCurrency),
            loadAccountForm: DefaultLoadAccountFormUseCase(repository: repository),
            saveAccount: DefaultSaveAccountUseCase(repository: repository),
            deleteAccount: DefaultDeleteAccountUseCase(repository: repository),
            reorderAccounts: DefaultReorderAccountsUseCase(repository: repository),
        )
    }
}

// MARK: - Implementations

@MainActor
public struct DefaultListAccountsUseCase: ListAccountsUseCase {
    private let repository: any LedgerRepository
    private let list = ListAccounts()

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func listAccounts(showHidden: Bool) throws -> AccountListing {
        try list(accounts: repository.accounts(), transactions: repository.transactions(), showHidden: showHidden)
    }
}

@MainActor
public struct DefaultComputeNetWealthUseCase: ComputeNetWealthUseCase {
    private let repository: any LedgerRepository
    private let compute: ComputeNetWealth

    public init(repository: any LedgerRepository, defaultCurrency: String = CurrencyCode.deviceDefault) {
        self.repository = repository
        self.compute = ComputeNetWealth(defaultCurrency: defaultCurrency)
    }

    public func netWealth() throws -> [CurrencyTotal] {
        try compute(accounts: repository.accounts(), transactions: repository.transactions())
    }
}

@MainActor
public struct DefaultLoadAccountFormUseCase: LoadAccountFormUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func formContext(editing accountID: UUID?, scheduledAccountIDs: Set<UUID>) throws -> AccountFormContext {
        let accounts = try repository.accounts()
        guard let accountID else {
            return AccountFormContext(accounts: accounts)
        }
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            throw AccountUseCaseError.accountNotFound
        }
        let locked = CurrencyLock.isLocked(
            accountID: accountID,
            transactions: try repository.transactions(),
            scheduledAccountIDs: scheduledAccountIDs,
        )
        return AccountFormContext(accounts: accounts, account: account, isCurrencyLocked: locked)
    }
}

@MainActor
public struct DefaultSaveAccountUseCase: SaveAccountUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func save(_ draft: AccountDraft, editing accountID: UUID?) throws -> Account {
        let accounts = try repository.accounts()
        let base: Account
        if let accountID {
            // Read the stored account again rather than trusting the form's copy, so an account deleted while
            // the form was open is never saved back.
            guard let existing = accounts.first(where: { $0.id == accountID }) else {
                throw AccountUseCaseError.accountNotFound
            }
            base = existing
        } else {
            base = Account(sortOrder: ReorderAccounts.nextSortOrder(after: accounts))
        }
        let account = draft.applied(to: base)
        try repository.saveAccount(account)
        return try repository.accounts().first { $0.id == account.id } ?? account
    }

    public func update(_ accountID: UUID, _ change: (inout Account) -> Void) throws {
        guard var account = try repository.accounts().first(where: { $0.id == accountID }) else {
            throw AccountUseCaseError.accountNotFound
        }
        change(&account)
        try repository.saveAccount(account)
    }
}

@MainActor
public struct DefaultDeleteAccountUseCase: DeleteAccountUseCase {
    private let repository: any LedgerRepository
    private let assess = AssessAccountDeletion()

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func deletionImpact(of accountID: UUID) throws -> AccountDeletionImpact {
        assess(accountID: accountID, transactions: try repository.transactions())
    }

    public func delete(_ accountID: UUID) throws {
        try repository.deleteAccount(id: accountID)
    }
}

@MainActor
public struct DefaultReorderAccountsUseCase: ReorderAccountsUseCase {
    private let repository: any LedgerRepository
    private let reorder = ReorderAccounts()

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func move(in group: AccountGroup, shown: [UUID], fromOffsets: IndexSet, toOffset: Int) throws {
        let accounts = try repository.accounts().filter { $0.deletedAt == nil && AccountGroup($0.type) == group }
        let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let shownAccounts = shown.compactMap { byID[$0] }
        guard shownAccounts.count == shown.count else {
            throw AccountUseCaseError.accountNotFound
        }
        let section = AccountOrder.sorted(accounts)
        for account in reorder(shownAccounts, fromOffsets: fromOffsets, toOffset: toOffset, within: section) {
            try repository.saveAccount(account)
        }
    }
}
