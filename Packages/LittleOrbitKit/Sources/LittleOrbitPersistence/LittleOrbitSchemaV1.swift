#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    // Migration steps live in docs/persistence-migration.md. V1 has no stages yet.

    public enum LittleOrbitSchemaV1: VersionedSchema {
        public static var versionIdentifier: Schema.Version {
            Schema.Version(LedgerSchemaVersion.major, LedgerSchemaVersion.minor, LedgerSchemaVersion.patch)
        }

        public static var models: [any PersistentModel.Type] {
            [
                AccountRecord.self,
                TransactionRecord.self,
                CategoryRecord.self,
                PayeeRecord.self,
                TagRecord.self,
                TransactionSplitRecord.self,
                AttachmentRecord.self,
                BudgetRecord.self,
                BudgetLimitRecord.self,
                ScheduledItemRecord.self,
                ScheduledOccurrenceRecord.self,
            ]
        }

        // @Model does not synthesize initializers. `init()` keeps the property defaults.
        @Model
        public final class AccountRecord {
            public var id: UUID = UUID()
            public var name: String = ""
            public var accountType: String = AccountType.checking.rawValue
            public var currencyCode: String = CurrencyCode.fallback
            public var openingBalanceMinor: Int64 = 0
            public var openingBalanceScale: Int16 = 0
            public var openingDate: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var iconName: String?
            public var colorHex: String?
            public var isHidden: Bool = false
            public var includeInNetWorth: Bool = true
            public var sortOrder: Double = 0
            public var notes: String?
            public var creditLimitMinor: Int64?
            public var creditLimitScale: Int16?
            public var showAvailableCredit: Bool = false
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.account)
            public var transactions: [TransactionRecord]? = []

            @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.transferAccount)
            public var incomingTransfers: [TransactionRecord]? = []

            public init() {}
        }

        @Model
        public final class TransactionRecord {
            public var id: UUID = UUID()
            // Not a constraint. Changing to or from a transfer is rejected in LedgerBook (#37).
            public var transactionType: String = TransactionType.expense.rawValue
            public var amountMinor: Int64 = 0
            public var amountScale: Int16 = 0
            public var date: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var timeZoneID: String = "UTC"
            public var details: String?
            public var note: String?
            public var destinationAmountMinor: Int64?
            public var destinationAmountScale: Int16?
            public var scheduledTemplateID: UUID?
            public var scheduledOccurrenceDate: Date?
            public var status: String = TransactionStatus.cleared.rawValue
            public var refundOfID: UUID?
            /// Marks an income transaction as a refund of an expense, so the app can still
            /// recognise a refund after its link is cleared (see #11).
            public var isRefund: Bool = false
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var account: AccountRecord?
            public var transferAccount: AccountRecord?
            public var category: CategoryRecord?
            public var payee: PayeeRecord?

            @Relationship(deleteRule: .nullify, inverse: \TagRecord.transactions)
            public var tags: [TagRecord]? = []

            @Relationship(deleteRule: .cascade, inverse: \TransactionSplitRecord.transaction)
            public var splits: [TransactionSplitRecord]? = []

            @Relationship(deleteRule: .cascade, inverse: \AttachmentRecord.transaction)
            public var attachments: [AttachmentRecord]? = []

            public init() {}
        }

        @Model
        public final class CategoryRecord {
            public var id: UUID = UUID()
            public var name: String = ""
            public var categoryKind: String = CategoryKind.expense.rawValue
            public var iconName: String?
            public var colorHex: String?
            public var sortOrder: Double = 0
            public var isArchived: Bool = false
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var parent: CategoryRecord?

            @Relationship(deleteRule: .cascade, inverse: \CategoryRecord.parent)
            public var children: [CategoryRecord]? = []

            @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.category)
            public var transactions: [TransactionRecord]? = []

            @Relationship(deleteRule: .nullify, inverse: \PayeeRecord.defaultCategory)
            public var defaultPayees: [PayeeRecord]? = []

            @Relationship(deleteRule: .nullify, inverse: \TransactionSplitRecord.category)
            public var splits: [TransactionSplitRecord]? = []

            /// The budgets that picked this category (#25).
            @Relationship(deleteRule: .nullify, inverse: \BudgetRecord.categories)
            public var budgets: [BudgetRecord]? = []

            public init() {}
        }

        @Model
        public final class PayeeRecord {
            public var id: UUID = UUID()
            public var name: String = ""
            public var lastUsedAt: Date?
            public var isArchived: Bool = false
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var defaultCategory: CategoryRecord?

            @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.payee)
            public var transactions: [TransactionRecord]? = []

            public init() {}
        }

        @Model
        public final class TagRecord {
            public var id: UUID = UUID()
            public var name: String = ""
            public var colorHex: String?
            public var sortOrder: Double = 0
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var transactions: [TransactionRecord]? = []

            public init() {}
        }

        @Model
        public final class TransactionSplitRecord {
            public var id: UUID = UUID()
            public var amountMinor: Int64 = 0
            public var amountScale: Int16 = 0
            public var note: String?
            public var sortOrder: Double = 0
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var transaction: TransactionRecord?
            public var category: CategoryRecord?

            public init() {}
        }

        @Model
        public final class AttachmentRecord {
            public var id: UUID = UUID()
            public var fileName: String = ""
            public var contentType: String = ""
            public var byteSize: Int64 = 0

            @Attribute(.externalStorage)
            public var data: Data?

            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?
            public var transaction: TransactionRecord?

            public init() {}
        }

        /// A budget (#25). Its start day is a calendar day, kept as year, month and day.
        @Model
        public final class BudgetRecord {
            public var id: UUID = UUID()
            public var name: String = ""
            public var currencyCode: String = CurrencyCode.fallback
            public var startYear: Int = 1970
            public var startMonth: Int = 1
            public var startDayOfMonth: Int = 1
            /// weekly, fortnightly, monthly, yearly or custom (`BudgetRecurrence.stored`).
            public var recurrenceKind: String = "monthly"
            /// day, week, month or year, for a custom repeat only.
            public var recurrenceUnit: String?
            /// 1–99, for a custom repeat only.
            public var recurrenceCount: Int?
            public var carriesOverUnspent: Bool = false
            public var carriesOverOverspending: Bool = false
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var categories: [CategoryRecord]? = []

            @Relationship(deleteRule: .cascade, inverse: \BudgetLimitRecord.budget)
            public var limits: [BudgetLimitRecord]? = []

            public init() {}
        }

        /// One entry in a budget's limit history: the amount applies from the period starting on its day.
        @Model
        public final class BudgetLimitRecord {
            public var id: UUID = UUID()
            public var amountMinor: Int64 = 0
            public var amountScale: Int16 = 0
            public var startYear: Int = 1970
            public var startMonth: Int = 1
            public var startDayOfMonth: Int = 1
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var budget: BudgetRecord?

            public init() {}
        }

        /// A scheduled item (#26). Days are kept as year, month and day. Its account, category and payee are IDs,
        /// not relationships, so deleting one never touches it here: `LedgerBook` updates or hides it (D288.1).
        @Model
        public final class ScheduledItemRecord {
            public var id: UUID = UUID()
            public var transactionType: String = TransactionType.expense.rawValue
            public var amountMinor: Int64 = 0
            public var amountScale: Int16 = 0
            public var destinationAmountMinor: Int64?
            public var destinationAmountScale: Int16?
            /// The currency the received amount was entered in (#207 B1). Optional, added in place: a development
            /// store made before it needs a reset.
            public var receivedCurrencyCode: String?
            public var accountID: UUID?
            public var transferAccountID: UUID?
            public var categoryID: UUID?
            public var payeeID: UUID?
            public var details: String?
            public var note: String?
            public var startYear: Int = 1970
            public var startMonth: Int = 1
            public var startDayOfMonth: Int = 1
            /// never or every (`ScheduleRepeat`).
            public var repeatKind: String = "never"
            /// day, week, month or year, for a repeating item only.
            public var repeatUnit: String?
            /// 1–99, for a repeating item only.
            public var repeatCount: Int?
            public var endYear: Int?
            public var endMonth: Int?
            public var endDayOfMonth: Int?
            public var resumesYear: Int?
            public var resumesMonth: Int?
            public var resumesDayOfMonth: Int?
            public var processesAutomatically: Bool = false
            public var notifiesWhenDue: Bool = false
            public var timeZoneID: String = "UTC"
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            @Relationship(deleteRule: .cascade, inverse: \ScheduledOccurrenceRecord.item)
            public var occurrences: [ScheduledOccurrenceRecord]? = []

            public init() {}
        }

        /// One occurrence of a scheduled item with a record, keyed by the item and its own day (#26): settled, kept
        /// due after an edit, or with its own values from "This occurrence only" (D45).
        @Model
        public final class ScheduledOccurrenceRecord {
            public var id: UUID = UUID()
            public var year: Int = 1970
            public var month: Int = 1
            public var dayOfMonth: Int = 1
            /// posted, skipped, pending or edited (`ScheduledOutcome`).
            public var outcome: String = ScheduledOutcome.posted.rawValue
            public var transactionID: UUID?
            /// `true` only when the app recorded it (S81, D354.1); unset for the user's Pay or Skip.
            public var recordedAutomatically: Bool?
            /// The occurrence's own fields (`ScheduledEditField` raw values, comma-separated), or `nil` with none. A
            /// field listed with a `nil` value below was cleared on purpose.
            public var editFields: String?
            /// The day the occurrence is due on instead of its own day.
            public var editYear: Int?
            public var editMonth: Int?
            public var editDayOfMonth: Int?
            /// Its own amount, in minor units at `editAmountScale` decimal places.
            public var editAmountMinor: Int64?
            public var editAmountScale: Int16?
            public var editAccountID: UUID?
            public var editTransferAccountID: UUID?
            /// Its own amount received, in minor units at `editDestinationAmountScale` decimal places, and the
            /// currency it was entered in (#207 B1).
            public var editDestinationAmountMinor: Int64?
            public var editDestinationAmountScale: Int16?
            public var editReceivedCurrencyCode: String?
            public var editCategoryID: UUID?
            public var editPayeeID: UUID?
            public var editDetails: String?
            public var editNote: String?
            public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
            public var deletedAt: Date?

            public var item: ScheduledItemRecord?

            public init() {}
        }
    }

    public enum LittleOrbitMigrationPlan: SchemaMigrationPlan {
        public static var schemas: [any VersionedSchema.Type] {
            [LittleOrbitSchemaV1.self]
        }

        public static var stages: [MigrationStage] {
            []
        }
    }

    @MainActor
    public enum LittleOrbitStore {
        public static func makeContainer(configuration: StoreConfiguration = .local) throws -> ModelContainer {
            if configuration.sync != .none {
                throw StoreError.syncNotImplemented
            }
            let modelConfiguration = try modelConfiguration(for: configuration)
            // The model-type initializer is what actually applies `LittleOrbitMigrationPlan`.
            return try ModelContainer(
                for: LittleOrbitSchemaV1.AccountRecord.self,
                LittleOrbitSchemaV1.TransactionRecord.self,
                LittleOrbitSchemaV1.CategoryRecord.self,
                LittleOrbitSchemaV1.PayeeRecord.self,
                LittleOrbitSchemaV1.TagRecord.self,
                LittleOrbitSchemaV1.TransactionSplitRecord.self,
                LittleOrbitSchemaV1.AttachmentRecord.self,
                LittleOrbitSchemaV1.BudgetRecord.self,
                LittleOrbitSchemaV1.BudgetLimitRecord.self,
                LittleOrbitSchemaV1.ScheduledItemRecord.self,
                LittleOrbitSchemaV1.ScheduledOccurrenceRecord.self,
                migrationPlan: LittleOrbitMigrationPlan.self,
                configurations: modelConfiguration,
            )
        }

        public static func makeRepository(
            configuration: StoreConfiguration = .local,
            now: @escaping @MainActor () -> Date = { Date() },
        ) throws -> SwiftDataLedgerRepository {
            if configuration.inMemory {
                let container = try makeContainer(configuration: configuration)
                return SwiftDataLedgerRepository(container: container, now: now, seedPendingInMemory: true)
            }
            var configuration = configuration
            let fileURL = try configuration.fileURL ?? StoreLocation.prepareStoreURL()
            configuration.fileURL = fileURL
            let marker = StoreLocation.pendingSeedMarkerURL(forStore: fileURL)
            // D293: a store file that doesn't exist yet is about to be created, so write the pending-seed marker
            // first, atomically. A crash between the two leaves the marker, and seeding still needs an empty store.
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try Data().write(to: marker, options: .atomic)
                } catch {
                    StoreLog.failure(.seedMarkerNotWritten, error)
                }
            }
            let container = try makeContainer(configuration: configuration)
            return SwiftDataLedgerRepository(container: container, now: now, seedMarker: marker)
        }

        private static func modelConfiguration(for configuration: StoreConfiguration) throws -> ModelConfiguration {
            if configuration.inMemory {
                return ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            }
            // Never SwiftData's shared `default.store`: with no explicit URL, use the app folder.
            let fileURL = try configuration.fileURL ?? StoreLocation.prepareStoreURL()
            return ModelConfiguration(url: fileURL, cloudKitDatabase: .none)
        }
    }
#endif
