import Foundation

/// The two sections of the account list. Credit cards and loans are Credit; every other type is Assets.
public enum AccountGroup: String, CaseIterable, Sendable {
    case assets
    case credit

    public init(_ type: AccountType) {
        self = type.isLiability ? .credit : .assets
    }
}

/// One account as the list shows it.
public struct AccountSummary: Identifiable, Equatable, Sendable {
    public var account: Account
    public var balance: Decimal
    public var creditStatus: CreditStatus?
    /// `false` shows "No transactions yet" (D114). Either side of a transfer counts; scheduled items don't.
    public var hasTransactions: Bool

    public init(account: Account, balance: Decimal, creditStatus: CreditStatus?, hasTransactions: Bool) {
        self.account = account
        self.balance = balance
        self.creditStatus = creditStatus
        self.hasTransactions = hasTransactions
    }

    public var id: UUID { account.id }
    public var group: AccountGroup { AccountGroup(account.type) }
}

public struct AccountListing: Equatable, Sendable {
    public var assets: [AccountSummary]
    public var credit: [AccountSummary]
    /// Hidden accounts, whether or not they are listed right now.
    public var hiddenCount: Int
    /// Every account, hidden ones included.
    public var totalCount: Int

    public init(
        assets: [AccountSummary] = [],
        credit: [AccountSummary] = [],
        hiddenCount: Int = 0,
        totalCount: Int = 0,
    ) {
        self.assets = assets
        self.credit = credit
        self.hiddenCount = hiddenCount
        self.totalCount = totalCount
    }

    /// No accounts at all: the first-run state.
    public var isEmpty: Bool { totalCount == 0 }

    public func summaries(in group: AccountGroup) -> [AccountSummary] {
        switch group {
        case .assets: assets
        case .credit: credit
        }
    }
}

/// Builds the account list. Hidden accounts are left out unless `showHidden` is on, and keep their place when
/// shown (D22, D109).
public struct ListAccounts: Sendable {
    public init() {}

    public func callAsFunction(
        accounts: [Account],
        transactions: [Transaction],
        showHidden: Bool,
    ) throws -> AccountListing {
        let live = accounts.filter { $0.deletedAt == nil }
        let snapshot = LedgerSnapshot(accounts: live, transactions: transactions)
        let referenced = AccountReferences.accountIDs(in: transactions)
        var listing = AccountListing(
            hiddenCount: live.filter(\.isHidden).count,
            totalCount: live.count,
        )
        for account in AccountOrder.sorted(live) where showHidden || !account.isHidden {
            let balance = try LedgerBook.balance(of: account.id, in: snapshot)
            let summary = AccountSummary(
                account: account,
                balance: balance,
                creditStatus: account.creditStatus(balance: balance),
                hasTransactions: referenced.contains(account.id),
            )
            switch summary.group {
            case .assets: listing.assets.append(summary)
            case .credit: listing.credit.append(summary)
            }
        }
        return listing
    }
}

/// The user's account order: `sortOrder`, then creation time, then id so the order is stable.
public enum AccountOrder {
    public static func sorted(_ accounts: [Account]) -> [Account] {
        accounts.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

enum AccountReferences {
    /// Accounts that a live transaction refers to, on either side of a transfer.
    static func accountIDs(in transactions: [Transaction]) -> Set<UUID> {
        var ids = Set<UUID>()
        for transaction in transactions where transaction.deletedAt == nil {
            if let accountID = transaction.accountID {
                ids.insert(accountID)
            }
            if let transferAccountID = transaction.transferAccountID {
                ids.insert(transferAccountID)
            }
        }
        return ids
    }

    static func refers(_ transaction: Transaction, to accountID: UUID) -> Bool {
        transaction.deletedAt == nil
            && (transaction.accountID == accountID || transaction.transferAccountID == accountID)
    }
}
