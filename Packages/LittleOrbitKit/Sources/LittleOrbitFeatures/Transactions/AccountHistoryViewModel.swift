import Foundation
import LittleOrbitDomain
import Observation

/// A day of history: "Today · Tue, 20 Oct" with its net change.
public struct TransactionDaySection: Identifiable, Equatable, Sendable {
    public var id: CalendarDay
    public var title: String
    public var netChangeText: String
    public var netChangeTone: AmountTone
    public var rows: [TransactionRowModel]
}

/// The confirmation for deleting several rows at once (D19). The delete is one Undo step, "Undo Delete 3
/// Transactions" (D161.2). Its destructive button says what it does and isn't the default (D164.5).
public struct BulkDeletePrompt: Equatable, Sendable, Identifiable {
    public var ids: [UUID]

    public var id: [UUID] { ids }
    public var title: String { "Delete \(ids.count) transactions?" }
    public var message: String { "You can undo this." }
    public var confirmTitle: String { "Delete \(ids.count) Transactions" }
}

/// One account's history (#23): current balance, Upcoming at the top with projected balances (D21), then days
/// newest first with the balance after each row. Every delete can be undone; multi-select deletes confirm first.
@MainActor
@Observable
public final class AccountHistoryViewModel {
    public let accountID: UUID
    public private(set) var accountName = ""
    public private(set) var currencyCode = ""
    public private(set) var balanceText = ""
    public private(set) var balanceTone: AmountTone = .neutral
    /// "After upcoming: ₹1,07,490.00", shown only when there are Upcoming rows.
    public private(set) var afterUpcomingText: String?
    public private(set) var upcomingTotalText: String?
    public private(set) var upcoming: [TransactionRowModel] = []
    public private(set) var sections: [TransactionDaySection] = []
    public private(set) var accountExists = true
    public var selection: Set<UUID> = []
    public var deletePrompt: BulkDeletePrompt?
    public var errorMessage: String?

    @ObservationIgnored private let accountHistory: any AccountHistoryUseCase
    @ObservationIgnored private let loadLedger: any LoadTransactionLedgerUseCase
    @ObservationIgnored private let changes: any TransactionChangesUseCase
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private let text: TransactionText
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: () -> Date

    public init(
        accountHistory: any AccountHistoryUseCase,
        loadLedger: any LoadTransactionLedgerUseCase,
        changes: any TransactionChangesUseCase,
        accountID: UUID,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.accountHistory = accountHistory
        self.loadLedger = loadLedger
        self.changes = changes
        self.accountID = accountID
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
    }

    /// The same, taking the use cases from one `TransactionUseCases` value.
    public convenience init(
        useCases: TransactionUseCases,
        accountID: UUID,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.init(
            accountHistory: useCases.accountHistory,
            loadLedger: useCases.loadLedger,
            changes: useCases.changes,
            accountID: accountID,
            locale: locale,
            timeZone: timeZone,
            now: now,
        )
    }

    public var isEmpty: Bool { upcoming.isEmpty && sections.isEmpty }

    /// Every row in display order: Upcoming, then history. The macOS table lists them in two sections.
    public var allRows: [TransactionRowModel] { upcoming + sections.flatMap(\.rows) }

    /// The scheduled item a projected Upcoming row comes from (S85), which a tap or double-click opens; `nil` for a
    /// stored transaction.
    public func scheduledItemID(of rowID: UUID) -> UUID? {
        upcoming.first { $0.id == rowID }?.scheduledItemID
    }

    /// The rows that are stored transactions, which can be edited or deleted; projected scheduled rows can't.
    public func storedIDs(_ ids: Set<UUID>) -> Set<UUID> {
        ids.filter { scheduledItemID(of: $0) == nil }
    }

    /// "5 selected" under the macOS table.
    public var selectionSummary: String? {
        selection.isEmpty ? nil : "\(selection.count) selected"
    }

    public func load() {
        do {
            let today = TransactionTiming.today(now(), timeZone: timeZone)
            guard let page = try accountHistory.history(of: accountID, today: today) else {
                accountExists = false
                upcoming = []
                sections = []
                return
            }
            let account = page.account
            let history = page.history
            accountExists = true
            accountName = account.name
            currencyCode = account.currencyCode
            let context = TransactionRowContext(
                account: account,
                accounts: page.ledger.accounts,
                categories: page.ledger.categories,
                payees: page.ledger.payees,
                formatter: formatter,
                text: text,
                today: today,
            )
            let currency = account.currencyCode
            balanceText = formatter.string(history.currentBalance, currencyCode: currency)
            balanceTone = history.currentBalance < 0 ? .negative : .neutral
            afterUpcomingText = history.balanceAfterUpcoming.map {
                "After upcoming: " + formatter.string($0, currencyCode: currency)
            }
            upcomingTotalText =
                history.upcoming.isEmpty
                ? nil : formatter.string(history.upcomingTotal, currencyCode: currency, showsPlus: true)
            upcoming = history.upcoming.map { context.row($0, isUpcoming: true) }
            sections = history.days.map { day in
                TransactionDaySection(
                    id: day.day,
                    title: text.dayTitle(day.day, today: today),
                    netChangeText: formatter.string(day.netChange, currencyCode: currency, showsPlus: true),
                    netChangeTone: day.netChange < 0 ? .negative : day.netChange > 0 ? .positive : .neutral,
                    rows: day.entries.map { context.row($0, isUpcoming: false) },
                )
            }
            let visible = Set(allRows.map(\.id))
            selection = selection.intersection(visible)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// The stored transactions behind the given rows, for editing.
    public func transactions(ids: Set<UUID>) -> [Transaction] {
        ((try? loadLedger.ledger().transactions) ?? []).filter { ids.contains($0.id) }
    }

    /// Deletes one transaction at once, with Undo (D19). Returns the change to record for Undo.
    @discardableResult
    public func delete(id: UUID) -> TransactionChange? {
        do {
            let change = try changes.remove(ids: [id])
            selection.remove(id)
            load()
            return change
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    /// The Delete key, swipe or context menu. One row is deleted at once with Undo; several ask first.
    @discardableResult
    public func requestDelete(ids: Set<UUID>) -> TransactionChange? {
        let ids = storedIDs(ids)
        if ids.count == 1, let id = ids.first {
            return delete(id: id)
        }
        if ids.count > 1 {
            let order = allRows.map(\.id)
            deletePrompt = BulkDeletePrompt(ids: order.filter { ids.contains($0) })
        }
        return nil
    }

    /// Deletes the confirmed rows as one all-or-nothing change and returns it, to register as one Undo step.
    @discardableResult
    public func confirmDelete() -> TransactionChange? {
        guard let prompt = deletePrompt else {
            return nil
        }
        deletePrompt = nil
        defer { load() }
        do {
            let change = try changes.remove(ids: prompt.ids)
            selection.subtract(prompt.ids)
            return change
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    public func cancelDelete() {
        deletePrompt = nil
    }

    /// The delete toast's wording for these rows, worked out before they go (D164.2): "Deleted Corner Bakery
    /// −€4.50", or "5 transactions deleted". This is only the base text: `WindowUndoHistory.showToast` adds
    /// where the change was when it isn't all on the window's screen (D165.1, D166.5).
    public func toastMessage(deleting ids: Set<UUID>) -> String {
        let rows = allRows.filter { ids.contains($0.id) }
        let single = rows.count == 1 ? rows.first.map { (title: $0.title, amount: $0.amountText) } : nil
        return UndoToast.message(single: single, count: ids.count, place: nil)
    }

    /// The signed amount in a single delete's toast, "−€4.50", kept whole on one line (D169, D170 U2); `nil`
    /// for a bulk delete.
    public func toastFigure(deleting ids: Set<UUID>) -> String? {
        let rows = allRows.filter { ids.contains($0.id) }
        return rows.count == 1 ? rows.first?.amountText : nil
    }

    static func message(for _: any Error) -> String {
        UndoText.saveFailed
    }
}
