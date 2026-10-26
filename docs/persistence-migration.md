# Persistence migration strategy

The ledger lives in `Packages/LittleOrbitKit`. Domain types and rules are in `LittleOrbitDomain`. `LittleOrbitPersistence` stores them. SwiftData is compiled only where `canImport(SwiftData)` is true (iOS, macOS, and watchOS). Linux builds and tests the domain rules and the in-memory repository.

## Current schema

| Piece | Value |
| --- | --- |
| Version | 1.0.0 (`LedgerSchemaVersion`) |
| SwiftData schema | `LittleOrbitSchemaV1` |
| Migration plan | `LittleOrbitMigrationPlan` |
| Stages | none |

`LittleOrbitMigrationPlan.schemas` lists versions from oldest to newest. With one version, opening an existing store applies no stage and leaves the records in place. The macOS repository test covers that round trip.

## Store

`StoreConfiguration` defaults to a local file and `StoreSyncMode.none`. The apps open it with `StoreConfiguration.appLocal()`, and `StoreLocation` picks the file (its folder is created on first open), never SwiftData's shared `default.store`:

1. If the app's Info.plist sets `LittleOrbitAppGroupIdentifier` and `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns a container for it, the store is `<group container>/LittleOrbit.store`.
2. Otherwise it is `Application Support/<bundle id>/LittleOrbit.store`.

Beside the store file sits `LittleOrbit.store.pending-seed` (`StoreLocation.pendingSeedMarkerURL(forStore:)`, D293), an empty file that `LittleOrbitStore.makeRepository` writes atomically just before the container creates a new store file. While it's there and the store holds no categories, accounts or transactions, launch seeds the default categories. A successful seed, a completed restore or a completed import removes it. A missing marker means seeded, so a store without one is never seeded. To reset a development install, delete the whole folder (or the app), not just `LittleOrbit.store`: deleting the store alone writes a new marker on the next launch, which seeds a fresh store, as it should. Backups hold the ledger's records, never files from this folder, so the marker isn't in them.

The container lookup is injectable (`AppGroupContainerLookup`), so both branches are unit-tested on Linux. `LittleOrbitStore.makeContainer` refuses any other sync mode and passes SwiftData's local-only database option. There is no CloudKit container, entitlement, or identifier in this package. Sync is a later change; the schema is shaped so that change does not have to rewrite V1.

No App Group is configured yet, so every build uses the Application Support fallback. Turning the group on needs the App Group entitlement and a provisioning profile (D154), plus the Info.plist key; the targets generate their Info.plist, so the key goes in an `INFOPLIST_FILE` merged with it. Moving an existing store into the group container is out of scope until then; nothing has shipped. On macOS, `containerURL(forSecurityApplicationGroupIdentifier:)` returns a URL even when the group isn't valid for the app (unlike iOS, which returns `nil`), so that change must also check on macOS that the container is accessible before choosing it.

## Writes

`SwiftDataLedgerRepository` is the store's single writer, on the main actor. It owns its `ModelContext`, with autosave off, and never calls `rollback()`, which traps in SwiftData on a to-many link that was never read (#265). A write first checks everything it could refuse (`LedgerWriteValidation`, with the same amount rule the record mapping calls), and on any later failure the repository drops the context for a new one and reads the store again. Nothing else in the apps may use a context of the store: no `mainContext`, `@Query` or SwiftUI `modelContext`. `mise run validate-project` fails on any of them in `Apps/` or the package sources.

## What V1 already contains

Phase 2 fields are columns and relationships on day one, with defaults, so using them later is not a migration:

- Transaction `status` (default `cleared`), `tags`, `splits`, `attachments`, `refundOfID`, `isRefund` (default `false`), `deletedAt`
- `deletedAt` on every entity, including splits and attachments. V1 ships with hard deletes and leaves it unused
  (always `nil`): `LedgerBook` removes the record outright and never sets `deletedAt` (accounts, transactions,
  splits, attachments, categories, payees, tags, budgets with their limits, and scheduled items with their
  occurrences)
- Tag, `TransactionSplit`, and `Attachment` entities
- `BudgetRecord` and `BudgetLimitRecord` (#25), added to V1 in place (D294.5). A budget links to the categories it
  picked (many-to-many, inverse `CategoryRecord.budgets`) and owns its limit history (cascade). Start days are kept
  as year, month and day. A changed V1 means a development store reset; nothing has shipped. Like every other
  record, a budget or limit carries `deletedAt` for sync but is removed outright when deleted. Restores check budgets
  with `LedgerBook.validateStoredBudgets` before either store replaces anything, so the two stores keep the same data.
  That includes refusing a category picked twice or two limits from one day, which the app never saves.
- `ScheduledItemRecord` and `ScheduledOccurrenceRecord` (#26), added to V1 in place before the first release
  (D294). An item keeps its account, transfer account, category and payee as optional UUID columns, not
  relationships, so an account delete can hide it and its Undo bring it back (D288.1). Days (start, end, resume) are
  year, month and day columns; the repeat is a kind (`never` or `every`), an optional unit and an optional count.
  An item owns its settled occurrences (cascade, inverse `ScheduledOccurrenceRecord.item`). Each occurrence's ID
  and the ID of the transaction it records come from the item ID and the occurrence's day, and the occurrence is
  saved in the same `save()` as its transaction, so an occurrence is recorded once across relaunches, windows and
  clock changes, and two devices derive the same IDs once sync arrives. A changed V1 means a development store reset.

Money is not a `Decimal` column. Each amount is an `Int64` number of minor units plus an `Int16` scale (`openingBalanceMinor` / `openingBalanceScale`, and the same pair for transaction amounts, destination amounts, credit limits, and splits). The domain type stays `Decimal`. 750.10 in a 2-digit currency is stored as minor units `75010` and scale `2`.

## Rules that keep a later sync possible

Do not relax these when adding a version:

- Every entity has a UUID `id` with a default, plus `createdAt` and `updatedAt`.
- Every attribute is optional or has a default. New attributes follow the same rule.
- Every relationship is optional and has an inverse. Delete rules are `.nullify` or `.cascade`, never `.deny`.
- No `@Attribute(.unique)`. The app enforces uniqueness in `LedgerBook`.
- Enums are stored as `String` raw values. Unknown values decode to a fallback (`AccountType.other`, `TransactionType.expense`, `TransactionStatus.cleared`, `CategoryKind.expense`).

## How to ship the next version

Until the first release there's no V2: `LittleOrbitSchemaV1` changes in place, with no migration between
development builds (D294.1). V1 is frozen at the first release (D294.2). These steps apply only after that.

V1 ships with hard deletes and `deletedAt` always `nil` (D317). A later version may start setting `deletedAt`
for sync tombstones without a store version bump: the column is already on every V1 entity, so it's a behaviour
change in `LedgerBook` and the stores only. Sync's first upload is the full current state, so records hard deleted
before then need no tombstone. Backups and restore must keep handling `deletedAt` as `nil`.

1. Leave `LittleOrbitSchemaV1` and its nested model classes unchanged. Editing them rewrites the version that devices already have.
2. Add `LittleOrbitSchemaV2` with a higher `Schema.Version`. Copy the V1 models and apply the change there.
3. Append `LittleOrbitSchemaV2.self` to `LittleOrbitMigrationPlan.schemas`.
4. Add one `MigrationStage` between V1 and V2.
5. Point `LittleOrbitStore` at the new schema only after the plan includes the stage. Keep `LedgerSchemaVersion` in step with that schema.
6. Add a repository test that writes a V1 store, opens it with the new plan, and checks the records.

Use a lightweight stage when the change only adds an optional or defaulted attribute, or an optional relationship with an inverse. SwiftData can infer that migration.

Use a custom stage when existing values change shape, split, or move. Do the work in `willMigrate` / `didMigrate`, and keep the V1 models available so the stage can read the old rows.

```swift
static var stages: [MigrationStage] {
    [migrateV1toV2]
}

static let migrateV1toV2 = MigrationStage.lightweight(
    fromVersion: LittleOrbitSchemaV1.self,
    toVersion: LittleOrbitSchemaV2.self
)
```

A custom stage uses `MigrationStage.custom(fromVersion:toVersion:willMigrate:didMigrate:)`.

## What does not belong in a migration of this schema

`ExchangeRate` is a new entity on its own ticket. Before the first release it goes straight into V1, as budgets and
scheduled items did (D294.5, D294). `AccountFolder` (#43) is not reserved here, because a placeholder shape would itself need a migration once the real fields are known. An optional relationship added then can be a lightweight stage.

The domain type is `TransactionCategory`. The SwiftData class stays `CategoryRecord`, so the stored entity name is unchanged. Deleting or merging a category updates the budgets that picked it: they pick the target instead, or drop it when its transactions are left uncategorised (D217.7, D295.1).
