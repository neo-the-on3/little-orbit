import Foundation

/// How many accounts, categories and payees an import would create (#60 “Preview”).
public struct ImportCreatedCounts: Equatable, Sendable {
    public var accounts: Int
    public var categories: Int
    public var payees: Int

    public init(accounts: Int = 0, categories: Int = 0, payees: Int = 0) {
        self.accounts = accounts
        self.categories = categories
        self.payees = payees
    }
}

/// One account's income and expense among the rows to import, in that account's currency. Transfers are
/// neither, so they're left out (D25).
public struct ImportAccountTotal: Equatable, Sendable, Identifiable {
    public var account: ImportRef
    public var income: Decimal
    public var expense: Decimal

    public var id: ImportRef {
        account
    }

    public init(account: ImportRef, income: Decimal = 0, expense: Decimal = 0) {
        self.account = account
        self.income = income
        self.expense = expense
    }
}

extension ImportPreview {
    /// What importing `selection` would create: each new account, category and payee once. A new
    /// subcategory under a new parent creates both.
    public func created(_ selection: Set<Int>) -> ImportCreatedCounts {
        var accounts: Set<ImportMatchKey> = []
        var categories: Set<ImportMatchKey> = []
        var payees: Set<ImportMatchKey> = []
        let choices = Dictionary(matches.map { ($0.key, $0.choice) }, uniquingKeysWith: { first, _ in first })
        for row in importable(selection) {
            guard let draft = row.draft else { continue }
            for case .new(let key)? in [draft.account, draft.toAccount] {
                accounts.insert(key)
            }
            if case .new(let key)? = draft.category {
                categories.insert(key)
                if case .subcategory(let kind, let parentKey) = key.kind {
                    let parent = ImportMatchKey(kind: .category(kind), nameKey: parentKey)
                    if case .new? = choices[parent] {
                        categories.insert(parent)
                    }
                }
            }
            if case .new(let key)? = draft.payee {
                payees.insert(key)
            }
        }
        return ImportCreatedCounts(accounts: accounts.count, categories: categories.count, payees: payees.count)
    }

    /// Income and expense per account among `selection`, in the order the accounts first appear. A refund
    /// counts as income, as it's stored.
    public func totals(_ selection: Set<Int>) -> [ImportAccountTotal] {
        var totals: [ImportRef: ImportAccountTotal] = [:]
        var order: [ImportRef] = []
        for row in importable(selection) {
            guard let draft = row.draft, draft.kind != .transfer else { continue }
            if totals[draft.account] == nil {
                totals[draft.account] = ImportAccountTotal(account: draft.account)
                order.append(draft.account)
            }
            if draft.kind == .expense {
                totals[draft.account]?.expense += draft.amount
            } else {
                totals[draft.account]?.income += draft.amount
            }
        }
        return order.compactMap { totals[$0] }
    }
}
