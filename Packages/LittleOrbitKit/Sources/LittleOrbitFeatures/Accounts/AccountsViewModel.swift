import Foundation
import LittleOrbitDomain
import Observation

/// The account list: the iOS home and the macOS sidebar (#22).
///
/// Depends only on the account use-case protocols, injected by the composition root. Every change is written at
/// once and the list reloads, so edits, hide/unhide, reorder and delete apply immediately.
@MainActor
@Observable
public final class AccountsViewModel {
    public private(set) var assets: [AccountRowModel] = []
    public private(set) var credit: [AccountRowModel] = []
    public private(set) var netWealth: [NetWealthLine] = []
    public private(set) var homeRows: [HomeRowModel] = HomeRowModel.rows(
        counts: PlannedItemCounts(),
        hasAnyTransaction: false,
    )
    public private(set) var hiddenCount = 0
    /// No accounts at all, hidden ones included.
    public private(set) var isFirstRun = true
    public var errorMessage: String?
    public var deletePrompt: AccountDeletePrompt?
    /// iOS reorder mode, entered with the Edit button and left with Done (D151). It only reorders:
    /// hide, exclude and delete are off until it ends. macOS drags rows directly and never sets it.
    public var isReordering = false
    public var showHidden = false {
        didSet {
            if showHidden != oldValue {
                load()
            }
        }
    }

    @ObservationIgnored private let listAccounts: any ListAccountsUseCase
    @ObservationIgnored private let computeNetWealth: any ComputeNetWealthUseCase
    @ObservationIgnored private let saveAccount: any SaveAccountUseCase
    @ObservationIgnored private let deleteAccount: any DeleteAccountUseCase
    @ObservationIgnored private let reorderAccounts: any ReorderAccountsUseCase
    @ObservationIgnored private let plannedItems: any PlannedItemsSource
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private var accounts: [Account] = []

    public init(
        listAccounts: any ListAccountsUseCase,
        computeNetWealth: any ComputeNetWealthUseCase,
        saveAccount: any SaveAccountUseCase,
        deleteAccount: any DeleteAccountUseCase,
        reorderAccounts: any ReorderAccountsUseCase,
        plannedItems: any PlannedItemsSource = NoPlannedItems(),
        locale: Locale = .current,
    ) {
        self.listAccounts = listAccounts
        self.computeNetWealth = computeNetWealth
        self.saveAccount = saveAccount
        self.deleteAccount = deleteAccount
        self.reorderAccounts = reorderAccounts
        self.plannedItems = plannedItems
        self.formatter = MoneyFormatter(locale: locale)
    }

    /// The same, taking the use cases from one `AccountUseCases` value.
    public convenience init(
        useCases: AccountUseCases,
        plannedItems: any PlannedItemsSource = NoPlannedItems(),
        locale: Locale = .current,
    ) {
        self.init(
            listAccounts: useCases.listAccounts,
            computeNetWealth: useCases.computeNetWealth,
            saveAccount: useCases.saveAccount,
            deleteAccount: useCases.deleteAccount,
            reorderAccounts: useCases.reorderAccounts,
            plannedItems: plannedItems,
            locale: locale,
        )
    }

    public var showHiddenTitle: String {
        "Show hidden accounts (\(hiddenCount))"
    }

    /// Net wealth on one line, as in the macOS sidebar footer: "₹16,650.50 · $1,240.00", or "—" with none.
    public var netWealthSummary: String {
        netWealth.isEmpty ? "—" : netWealth.map(\.text).joined(separator: " · ")
    }

    /// VoiceOver label for the iOS All Accounts row: the row name, then the totals.
    public var allAccountsAccessibilityLabel: String {
        "All Accounts, net wealth \(netWealthSummary)"
    }

    public func rows(in group: AccountGroup) -> [AccountRowModel] {
        switch group {
        case .assets: assets
        case .credit: credit
        }
    }

    public func row(id: UUID) -> AccountRowModel? {
        (assets + credit).first { $0.id == id }
    }

    public func account(id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    public func load() {
        do {
            let listing = try listAccounts.listAccounts(showHidden: showHidden)
            accounts = (listing.assets + listing.credit).map(\.account)
            assets = listing.assets.map { AccountRowModel(summary: $0, formatter: formatter) }
            credit = listing.credit.map { AccountRowModel(summary: $0, formatter: formatter) }
            hiddenCount = listing.hiddenCount
            isFirstRun = listing.isEmpty
            netWealth = try computeNetWealth.netWealth()
                .map { total in
                    NetWealthLine(
                        currencyCode: total.currencyCode,
                        text: formatter.string(total.amount, currencyCode: total.currencyCode),
                    )
                }
            homeRows = HomeRowModel.rows(
                counts: plannedItems.plannedItemCounts(),
                hasAnyTransaction: listing.hasAnyTransaction,
            )
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Whether row actions (context menu, swipe, hide, exclude, delete) are available.
    public var allowsRowActions: Bool { !isReordering }

    public func setHidden(_ hidden: Bool, accountID: UUID) {
        guard allowsRowActions else {
            return
        }
        perform { try saveAccount.update(accountID) { $0.isHidden = hidden } }
    }

    public func setExcluded(_ excluded: Bool, accountID: UUID) {
        guard allowsRowActions else {
            return
        }
        perform { try saveAccount.update(accountID) { $0.includeInNetWorth = !excluded } }
    }

    /// Reorders within one section, with the same offsets SwiftUI's `onMove` passes. The use case keeps hidden
    /// accounts in the section in place (D109).
    public func move(in group: AccountGroup, fromOffsets: IndexSet, toOffset: Int) {
        let shown = rows(in: group).map(\.id)
        perform {
            try reorderAccounts.move(in: group, shown: shown, fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    public func requestDelete(accountID: UUID) {
        guard allowsRowActions, let account = account(id: accountID) else {
            return
        }
        do {
            let impact = try deleteAccount.deletionImpact(of: accountID)
            deletePrompt = AccountDeletePrompt(account: account, impact: impact)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Deletes the account with its transactions, transfers in or out, and their attachments (D19), and
    /// returns the change to record as one step, "Undo Delete Account …" (#93). `nil` if it failed.
    @discardableResult
    public func confirmDelete() -> TransactionChange? {
        guard let prompt = deletePrompt else {
            return nil
        }
        deletePrompt = nil
        var change: TransactionChange?
        perform { change = .removedAccount(try deleteAccount.delete(prompt.accountID)) }
        return change
    }

    /// The safer default in the delete confirmation.
    public func hideInsteadOfDeleting() {
        guard let prompt = deletePrompt else {
            return
        }
        deletePrompt = nil
        setHidden(true, accountID: prompt.accountID)
    }

    public func cancelDelete() {
        deletePrompt = nil
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = Self.message(for: error)
        }
        load()
    }

    static func message(for error: any Error) -> String {
        if let validation = error as? LedgerValidationError, validation == .currencyLocked {
            return CurrencyLock.message
        }
        if let useCase = error as? AccountUseCaseError, useCase == .accountNotFound {
            return "This account was deleted. The list has been refreshed."
        }
        return "Something went wrong saving your change. Please try again."
    }
}
