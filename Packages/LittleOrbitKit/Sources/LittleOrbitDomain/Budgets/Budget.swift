import Foundation

/// A spending limit on a group of expense categories that resets each period (#25).
///
/// - Counts only expenses from accounts in `currencyCode` (D17).
/// - `categoryIDs` are the categories the user picked. A parent also covers its subcategories, now and later
///   (D217.1), which `BudgetCategories.covered(by:in:)` works out from the current tree.
/// - Periods start on `startDay` and repeat by `recurrence` (D24, D26, D60). See `BudgetSchedule`.
/// - `limits` is the limit history: each one applies from its `startDay`, so a limit change applies from one
///   period on and earlier periods keep theirs (#25).
public struct Budget: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var currencyCode: String
    public var categoryIDs: [UUID]
    public var startDay: CalendarDay
    public var recurrence: BudgetRecurrence
    public var limits: [BudgetLimit]
    /// What's left unspent at a period's end is added to the next period.
    public var carriesOverUnspent: Bool
    /// Going over at a period's end is taken from the next period.
    public var carriesOverOverspending: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Kept for sync like every V1 record's (`docs/persistence-migration.md`). Deleting a budget removes it
    /// outright, as other records' deletes do, so the app never sets it yet; lists still skip one that has it.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String = "",
        currencyCode: String = CurrencyCode.fallback,
        categoryIDs: [UUID] = [],
        startDay: CalendarDay,
        recurrence: BudgetRecurrence = .monthly,
        limits: [BudgetLimit] = [],
        carriesOverUnspent: Bool = false,
        carriesOverOverspending: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.categoryIDs = categoryIDs
        self.startDay = startDay
        self.recurrence = recurrence
        self.limits = limits
        self.carriesOverUnspent = carriesOverUnspent
        self.carriesOverOverspending = carriesOverOverspending
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    /// A budget with one limit from its first period.
    public init(
        id: UUID = UUID(),
        name: String,
        currencyCode: String = CurrencyCode.fallback,
        categoryIDs: [UUID],
        startDay: CalendarDay,
        recurrence: BudgetRecurrence = .monthly,
        limit: Decimal,
        carriesOverUnspent: Bool = false,
        carriesOverOverspending: Bool = false,
        createdAt: Date = Date(),
    ) {
        self.init(
            id: id,
            name: name,
            currencyCode: currencyCode,
            categoryIDs: categoryIDs,
            startDay: startDay,
            recurrence: recurrence,
            limits: [BudgetLimit(startDay: startDay, amount: limit, createdAt: createdAt)],
            carriesOverUnspent: carriesOverUnspent,
            carriesOverOverspending: carriesOverOverspending,
            createdAt: createdAt,
        )
    }

    /// When each period starts and ends.
    public var schedule: BudgetSchedule {
        BudgetSchedule(startDay: startDay, recurrence: recurrence)
    }

    /// The limit for the period starting on `periodStart`: the latest one that applies from that day or
    /// earlier. The first limit covers anything before it.
    public func limit(forPeriodStartingOn periodStart: CalendarDay) -> Decimal {
        Self.limit(forPeriodStartingOn: periodStart, in: orderedLimits)
    }

    /// The limit history by start day, to sort once for many periods (#174 review NB3).
    public var orderedLimits: [BudgetLimit] {
        limits.sorted { $0.startDay < $1.startDay }
    }

    /// `limit(forPeriodStartingOn:)` from limits already in `orderedLimits` order.
    public static func limit(forPeriodStartingOn periodStart: CalendarDay, in ordered: [BudgetLimit]) -> Decimal {
        ordered.last { $0.startDay <= periodStart }?.amount ?? ordered.first?.amount ?? 0
    }
}

/// One entry in a budget's limit history: `amount` applies to every period starting on `startDay` or later,
/// until the next entry.
public struct BudgetLimit: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var startDay: CalendarDay
    public var amount: Decimal
    public var createdAt: Date
    public var updatedAt: Date
    /// Kept for sync like every V1 record's (`docs/persistence-migration.md`). Budget changes remove a limit
    /// outright, as other records' deletes do, so the app never sets it yet.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        startDay: CalendarDay,
        amount: Decimal,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.startDay = startDay
        self.amount = amount
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

/// How often a budget's periods repeat (#25): the four presets, or every 1–99 days, weeks, months or years
/// from the start day. There's no one-off date range.
///
/// A backup keeps it in the store's shape, `{"kind": "custom", "unit": "week", "count": 3}` or `{"kind": "monthly"}`,
/// so renaming a case can't change format 1 (#174 review NB1). A kind or unit it doesn't know doesn't decode.
public enum BudgetRecurrence: Hashable, Sendable, Codable {
    case weekly
    case fortnightly
    case monthly
    case yearly
    case custom(every: Int, unit: BudgetRecurrenceUnit)

    /// The allowed counts for a custom repeat (#25 PM answer 2, S16).
    public static let customRange = 1...99

    /// The step between period starts.
    public var step: (count: Int, unit: BudgetRecurrenceUnit) {
        switch self {
        case .weekly: (1, .week)
        case .fortnightly: (2, .week)
        case .monthly: (1, .month)
        case .yearly: (1, .year)
        case .custom(let every, let unit): (every, unit)
        }
    }

    /// A custom count outside 1–99 can't be saved.
    public var isValid: Bool {
        Self.customRange.contains(step.count)
    }
}

public enum BudgetRecurrenceUnit: String, CaseIterable, Hashable, Sendable, Codable {
    case day
    case week
    case month
    case year
}

extension BudgetRecurrence {
    /// How the store keeps a repeat: its kind, plus the unit and count for a custom one.
    public struct Stored: Equatable, Sendable {
        public var kind: String
        public var unit: String?
        public var count: Int?

        public init(kind: String, unit: String? = nil, count: Int? = nil) {
            self.kind = kind
            self.unit = unit
            self.count = count
        }
    }

    public var stored: Stored {
        switch self {
        case .weekly: Stored(kind: "weekly")
        case .fortnightly: Stored(kind: "fortnightly")
        case .monthly: Stored(kind: "monthly")
        case .yearly: Stored(kind: "yearly")
        case .custom(let every, let unit): Stored(kind: "custom", unit: unit.rawValue, count: every)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, unit, count
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "weekly": self = .weekly
        case "fortnightly": self = .fortnightly
        case "monthly": self = .monthly
        case "yearly": self = .yearly
        case "custom":
            let unit = try container.decode(String.self, forKey: .unit)
            guard let parsed = BudgetRecurrenceUnit(rawValue: unit) else {
                throw DecodingError.dataCorruptedError(forKey: .unit, in: container, debugDescription: "Unknown unit")
            }
            self = .custom(every: try container.decode(Int.self, forKey: .count), unit: parsed)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown kind")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let stored = self.stored
        try container.encode(stored.kind, forKey: .kind)
        try container.encodeIfPresent(stored.unit, forKey: .unit)
        try container.encodeIfPresent(stored.count, forKey: .count)
    }

    /// The repeat a store's values describe. Anything it doesn't recognise reads as monthly, the form's default.
    public init(_ stored: Stored) {
        switch stored.kind {
        case "weekly": self = .weekly
        case "fortnightly": self = .fortnightly
        case "yearly": self = .yearly
        case "custom":
            if let unit = stored.unit.flatMap(BudgetRecurrenceUnit.init(rawValue:)), let count = stored.count {
                self = .custom(every: count, unit: unit)
            } else {
                self = .monthly
            }
        default: self = .monthly
        }
    }
}
