import Foundation

/// One line of the split editor before it is saved: a category, an amount or a blank, and a note (D40, D64).
/// Payee and tags stay on the whole transaction.
public struct SplitLineDraft: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var categoryID: UUID?
    /// `nil` for a blank (auto) line, which shares what is left of the total with the other blank lines (D64).
    public var amount: Decimal?
    public var note: String?

    public init(id: UUID = UUID(), categoryID: UUID? = nil, amount: Decimal? = nil, note: String? = nil) {
        self.id = id
        self.categoryID = categoryID
        self.amount = amount
        self.note = note
    }

    /// The editor line for a saved split line, which always has an amount.
    public init(_ split: TransactionSplit) {
        self.init(id: split.id, categoryID: split.categoryID, amount: split.amount, note: split.note)
    }
}

/// What stops one split line from saving. The editor shows it on that line (D64).
public enum SplitLineIssue: Equatable, Sendable {
    case missingCategory
    /// The line's amount, entered or worked out, is 0 or less. Every line must be above 0 (D64, S3).
    case amountNotPositive
    /// The line is past `SplitPlan.maximumLines`.
    case overLineLimit
}

/// Whether the lines add up to the total.
public enum SplitTotalIssue: Equatable, Sendable {
    /// The lines are this much more than the total.
    case over(Decimal)
    /// This much of the total is on no line yet. Nothing moves to another line by itself (D117.6).
    case leftToAssign(Decimal)
}

/// One line with its amount worked out.
public struct SplitLine: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var categoryID: UUID?
    public var amount: Decimal
    /// The line was blank, so its amount is its share of the remainder (D64).
    public var isAuto: Bool
    public var note: String?
    public var issues: [SplitLineIssue]
}

/// The split editor's lines resolved against the transaction total (D64, D117.6).
///
/// Blank lines share the remainder equally, in the currency's minor units, and the leftover minor unit goes to
/// the last blank line: ₹100 over 3 blank lines is ₹33.33, ₹33.33 and ₹33.34. When the entered amounts already
/// reach or pass the total, blank lines get 0 and are blocked (S3).
public struct SplitPlan: Equatable, Sendable {
    /// The most lines one split can have (D64).
    public static let maximumLines = 20

    public var total: Decimal
    public var lines: [SplitLine]
    public var totalIssue: SplitTotalIssue?

    /// Fewer than two lines: saving makes the transaction a normal single-category one (D64, S8).
    public var isSingleCategory: Bool {
        lines.count < 2
    }

    /// The total less the lines: positive when some is left to assign, negative when the lines are over.
    public var remaining: Decimal {
        total - lines.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Two or more lines, none with an issue, adding up to the total.
    public var canSave: Bool {
        !isSingleCategory && totalIssue == nil && lines.allSatisfy(\.issues.isEmpty)
    }

    public init(_ drafts: [SplitLineDraft], total: Decimal, currencyCode: String) {
        self.total = total
        let scale = CurrencyCode.minorUnits(for: currencyCode) ?? 2
        let entered = drafts.compactMap(\.amount).reduce(Decimal(0), +)
        let blanks = drafts.filter { $0.amount == nil }.map(\.id)
        let shares = Self.shares(of: total - entered, among: blanks.count, scale: scale)
        var shareByLine: [UUID: Decimal] = [:]
        for (id, share) in zip(blanks, shares) {
            shareByLine[id] = share
        }
        lines = drafts.enumerated()
            .map { index, draft in
                let amount = draft.amount ?? shareByLine[draft.id] ?? 0
                var issues: [SplitLineIssue] = []
                if index >= Self.maximumLines {
                    issues.append(.overLineLimit)
                }
                if amount <= 0 {
                    issues.append(.amountNotPositive)
                }
                if draft.categoryID == nil {
                    issues.append(.missingCategory)
                }
                return SplitLine(
                    id: draft.id,
                    categoryID: draft.categoryID,
                    amount: amount,
                    isAuto: draft.amount == nil,
                    note: draft.note,
                    issues: issues,
                )
            }
        let difference = total - lines.reduce(Decimal(0)) { $0 + $1.amount }
        if difference < 0 {
            totalIssue = .over(-difference)
        } else if difference > 0 {
            totalIssue = .leftToAssign(difference)
        } else {
            totalIssue = nil
        }
    }

    /// The lines to store for `transactionID`, in editor order. Call only when `canSave` is true.
    public func splits(for transactionID: UUID) -> [TransactionSplit] {
        lines.enumerated()
            .map { index, line in
                TransactionSplit(
                    id: line.id,
                    transactionID: transactionID,
                    categoryID: line.categoryID,
                    amount: line.amount,
                    note: line.note,
                    sortOrder: Double(index),
                )
            }
    }

    /// The categories another line already uses, which `line`'s picker shows disabled. The line's own category
    /// stays selectable, so no category can be on two lines (D117.1).
    public static func categoriesUsedElsewhere(than line: UUID, in drafts: [SplitLineDraft]) -> Set<UUID> {
        Set(drafts.filter { $0.id != line }.compactMap(\.categoryID))
    }

    /// `remainder` shared among `count` lines in minor units of `scale`, the last taking the leftover.
    static func shares(of remainder: Decimal, among count: Int, scale: Int) -> [Decimal] {
        guard count > 0 else {
            return []
        }
        guard remainder > 0 else {
            return Array(repeating: 0, count: count)
        }
        var exact = remainder / Decimal(count)
        var share = Decimal()
        NSDecimalRound(&share, &exact, scale, .down)
        let last = remainder - share * Decimal(count - 1)
        return Array(repeating: share, count: count - 1) + [last]
    }
}
