import Foundation

/// What a name in the file stands for in the matching step.
public enum ImportMatchKind: Hashable, Sendable {
    case account
    case category(CategoryKind)
    /// A subcategory under the parent with this name key.
    case subcategory(CategoryKind, parentKey: String)
    case payee
}

/// One distinct name in the file: its kind and its name key (case- and space-insensitive).
public struct ImportMatchKey: Hashable, Sendable {
    public var kind: ImportMatchKind
    public var nameKey: String

    public init(kind: ImportMatchKind, nameKey: String) {
        self.kind = kind
        self.nameKey = nameKey
    }

    public init(kind: ImportMatchKind, name: String) {
        self.init(kind: kind, nameKey: ImportText.nameKey(name))
    }
}

/// What a name becomes: a new record, or an existing one.
public enum ImportMatchChoice: Hashable, Sendable {
    case new
    case existing(UUID)
}

/// A record an import draft refers to: one already in the ledger, or one the import creates for a match.
public enum ImportRef: Hashable, Sendable {
    case existing(UUID)
    case new(ImportMatchKey)
}

/// One row of the matching step (#30 AC 3).
public struct ImportMatch: Equatable, Sendable, Identifiable {
    public var key: ImportMatchKey
    /// The name as the file first writes it, trimmed.
    public var name: String
    /// For a subcategory, its parent as the file writes it.
    public var parentName: String?
    public var rowCount: Int
    /// The current choice: the user's, or the automatic one.
    public var choice: ImportMatchChoice
    /// What matching by name picked before any change.
    public var automaticChoice: ImportMatchChoice
    /// For a new account: the currency its rows use.
    public var currencyCode: String?

    public var id: ImportMatchKey {
        key
    }

    public init(
        key: ImportMatchKey,
        name: String,
        parentName: String? = nil,
        rowCount: Int,
        choice: ImportMatchChoice,
        automaticChoice: ImportMatchChoice,
        currencyCode: String? = nil,
    ) {
        self.key = key
        self.name = name
        self.parentName = parentName
        self.rowCount = rowCount
        self.choice = choice
        self.automaticChoice = automaticChoice
        self.currencyCode = currencyCode
    }

    public var isRemapped: Bool {
        choice != automaticChoice
    }
}

/// What the user decided before Review: the target account for a file without an Account column, changed
/// matches, and currencies for new accounts.
public struct ImportChoices: Equatable, Sendable {
    public var targetAccountID: UUID?
    public var matches: [ImportMatchKey: ImportMatchChoice]
    /// Currency codes for new accounts, by account name key (#60's preview currency picker).
    public var newAccountCurrencies: [String: String]

    public init(
        targetAccountID: UUID? = nil,
        matches: [ImportMatchKey: ImportMatchChoice] = [:],
        newAccountCurrencies: [String: String] = [:],
    ) {
        self.targetAccountID = targetAccountID
        self.matches = matches
        self.newAccountCurrencies = newAccountCurrencies
    }
}

/// Matches the file's names to the ledger: trimmed and case-insensitive, existing records first, a new record
/// otherwise (D38, design rule). The user's choices override it. The ledger's names are indexed once per plan,
/// so a plan is linear in rows plus records, not rows × records (Tech Architect NB1 on #190).
struct ImportMatcher {
    let ledger: TransactionLedger
    let choices: ImportChoices
    let defaultCurrency: String
    private(set) var matches: [ImportMatchKey: ImportMatch] = [:]
    private var order: [ImportMatchKey] = []
    private let index: ImportNameIndex

    init(ledger: TransactionLedger, choices: ImportChoices, defaultCurrency: String) {
        self.ledger = ledger
        self.choices = choices
        self.defaultCurrency = defaultCurrency
        index = ImportNameIndex(ledger)
    }

    var orderedMatches: [ImportMatch] {
        order.compactMap { matches[$0] }
    }

    func account(_ ref: ImportRef) -> Account? {
        guard case .existing(let id) = ref else {
            return nil
        }
        return index.accountsByID[id]
    }

    func currency(of ref: ImportRef) -> String {
        switch ref {
        case .existing(let id):
            return index.accountsByID[id]?.currencyCode ?? defaultCurrency
        case .new(let key):
            return matches[key]?.currencyCode ?? defaultCurrency
        }
    }

    // MARK: Accounts

    mutating func account(named name: String, currency: String?) -> ImportRef {
        let key = ImportMatchKey(kind: .account, name: name)
        let automatic: ImportMatchChoice = index.liveAccounts[key.nameKey].map { .existing($0) } ?? .new
        let choice = note(key, name: name, automatic: automatic)
        if case .new = choice, matches[key]?.currencyCode == nil {
            let newCurrency = choices.newAccountCurrencies[key.nameKey] ?? currency ?? defaultCurrency
            matches[key]?.currencyCode = newCurrency
        }
        return ref(for: key, choice)
    }

    // MARK: Categories

    mutating func category(_ path: ImportCategoryPath, kind: CategoryKind) -> ImportRef {
        guard let parentName = path.parent else {
            let key = ImportMatchKey(kind: .category(kind), name: path.name)
            let topLevel = index.topLevel[ImportNameIndex.KindKey(kind: kind, nameKey: key.nameKey)]
            let subcategories = index.subcategories[ImportNameIndex.KindKey(kind: kind, nameKey: key.nameKey)] ?? []
            let found = topLevel ?? (subcategories.count == 1 ? subcategories[0] : nil)
            let choice = note(key, name: path.name, automatic: found.map { .existing($0) } ?? .new)
            return ref(for: key, choice)
        }
        let parentKey = ImportMatchKey(kind: .category(kind), name: parentName)
        let parent = index.topLevel[ImportNameIndex.KindKey(kind: kind, nameKey: parentKey.nameKey)]
        let parentChoice = note(parentKey, name: parentName, automatic: parent.map { .existing($0) } ?? .new)
        let key = ImportMatchKey(kind: .subcategory(kind, parentKey: parentKey.nameKey), name: path.name)
        var automatic = ImportMatchChoice.new
        if case .existing(let parentID) = parentChoice,
            let child = index.children[ImportNameIndex.ChildKey(parentID: parentID, kind: kind, nameKey: key.nameKey)]
        {
            automatic = .existing(child)
        }
        let choice = note(key, name: path.name, parentName: parentName, automatic: automatic)
        return ref(for: key, choice)
    }

    // MARK: Payees

    mutating func payee(named name: String) -> ImportRef {
        let key = ImportMatchKey(kind: .payee, name: name)
        let automatic: ImportMatchChoice = index.livePayees[key.nameKey].map { .existing($0) } ?? .new
        return ref(for: key, note(key, name: name, automatic: automatic))
    }

    // MARK: Pieces

    private mutating func note(
        _ key: ImportMatchKey,
        name: String,
        parentName: String? = nil,
        automatic: ImportMatchChoice,
    ) -> ImportMatchChoice {
        if var match = matches[key] {
            match.rowCount += 1
            matches[key] = match
            return match.choice
        }
        var choice = choices.matches[key] ?? automatic
        if case .existing(let id) = choice, !index.exists(id, for: key.kind) {
            choice = automatic
        }
        matches[key] = ImportMatch(
            key: key,
            name: name,
            parentName: parentName,
            rowCount: 1,
            choice: choice,
            automaticChoice: automatic,
        )
        order.append(key)
        return choice
    }

    private func ref(for key: ImportMatchKey, _ choice: ImportMatchChoice) -> ImportRef {
        switch choice {
        case .existing(let id): .existing(id)
        case .new: .new(key)
        }
    }
}

/// The ledger's live accounts, categories and payees by name key and by id, built once per plan. Where
/// several records share a name key, the first in the ledger's order wins, as the earlier scans picked.
struct ImportNameIndex {
    struct KindKey: Hashable {
        var kind: CategoryKind
        var nameKey: String
    }

    struct ChildKey: Hashable {
        var parentID: UUID
        var kind: CategoryKind
        var nameKey: String
    }

    let accountsByID: [UUID: Account]
    let liveAccounts: [String: UUID]
    let livePayees: [String: UUID]
    let topLevel: [KindKey: UUID]
    /// Live subcategories by kind and name key, in the ledger's order.
    let subcategories: [KindKey: [UUID]]
    let children: [ChildKey: UUID]
    private let liveAccountIDs: Set<UUID>
    private let livePayeeIDs: Set<UUID>
    private let liveCategoryKinds: [UUID: CategoryKind]

    init(_ ledger: TransactionLedger) {
        var accountsByID: [UUID: Account] = [:]
        var liveAccounts: [String: UUID] = [:]
        var liveAccountIDs = Set<UUID>()
        for account in ledger.accounts {
            if accountsByID[account.id] == nil {
                accountsByID[account.id] = account
            }
            guard account.deletedAt == nil else { continue }
            liveAccountIDs.insert(account.id)
            let key = ImportText.nameKey(account.name)
            if liveAccounts[key] == nil {
                liveAccounts[key] = account.id
            }
        }
        var livePayees: [String: UUID] = [:]
        var livePayeeIDs = Set<UUID>()
        for payee in ledger.payees where payee.deletedAt == nil {
            livePayeeIDs.insert(payee.id)
            let key = ImportText.nameKey(payee.name)
            if livePayees[key] == nil {
                livePayees[key] = payee.id
            }
        }
        var topLevel: [KindKey: UUID] = [:]
        var subcategories: [KindKey: [UUID]] = [:]
        var children: [ChildKey: UUID] = [:]
        var liveCategoryKinds: [UUID: CategoryKind] = [:]
        for category in ledger.categories where category.deletedAt == nil {
            liveCategoryKinds[category.id] = category.kind
            let key = KindKey(kind: category.kind, nameKey: ImportText.nameKey(category.name))
            if let parentID = category.parentID {
                subcategories[key, default: []].append(category.id)
                let child = ChildKey(parentID: parentID, kind: category.kind, nameKey: key.nameKey)
                if children[child] == nil {
                    children[child] = category.id
                }
            } else if topLevel[key] == nil {
                topLevel[key] = category.id
            }
        }
        self.accountsByID = accountsByID
        self.liveAccounts = liveAccounts
        self.livePayees = livePayees
        self.topLevel = topLevel
        self.subcategories = subcategories
        self.children = children
        self.liveAccountIDs = liveAccountIDs
        self.livePayeeIDs = livePayeeIDs
        self.liveCategoryKinds = liveCategoryKinds
    }

    /// Whether a live record of `kind` has this id: a Match choice whose record has gone falls back.
    func exists(_ id: UUID, for kind: ImportMatchKind) -> Bool {
        switch kind {
        case .account:
            liveAccountIDs.contains(id)
        case .category(let categoryKind), .subcategory(let categoryKind, _):
            liveCategoryKinds[id] == categoryKind
        case .payee:
            livePayeeIDs.contains(id)
        }
    }
}
