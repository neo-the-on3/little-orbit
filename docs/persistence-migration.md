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

The container lookup is injectable (`AppGroupContainerLookup`), so both branches are unit-tested on Linux. `LittleOrbitStore.makeContainer` refuses any other sync mode and passes SwiftData's local-only database option. There is no CloudKit container, entitlement, or identifier in this package. Sync is a later change; the schema is shaped so that change does not have to rewrite V1.

No App Group is configured yet, so every build uses the Application Support fallback. Turning the group on needs the App Group entitlement and a provisioning profile (D154), plus the Info.plist key; the targets generate their Info.plist, so the key goes in an `INFOPLIST_FILE` merged with it. Moving an existing store into the group container is out of scope until then; nothing has shipped. On macOS, `containerURL(forSecurityApplicationGroupIdentifier:)` returns a URL even when the group isn't valid for the app (unlike iOS, which returns `nil`), so that change must also check on macOS that the container is accessible before choosing it.

## What V1 already contains

Phase 2 fields are columns and relationships on day one, with defaults, so using them later is not a migration:

- Transaction `status` (default `cleared`), `tags`, `splits`, `attachments`, `refundOfID`, `isRefund` (default `false`), `deletedAt`
- `deletedAt` on every entity, including splits and attachments
- Tag, `TransactionSplit`, and `Attachment` entities

Money is not a `Decimal` column. Each amount is an `Int64` number of minor units plus an `Int16` scale (`openingBalanceMinor` / `openingBalanceScale`, and the same pair for transaction amounts, destination amounts, credit limits, and splits). The domain type stays `Decimal`. 750.10 in a 2-digit currency is stored as minor units `75010` and scale `2`.

## Rules that keep a later sync possible

Do not relax these when adding a version:

- Every entity has a UUID `id` with a default, plus `createdAt` and `updatedAt`.
- Every attribute is optional or has a default. New attributes follow the same rule.
- Every relationship is optional and has an inverse. Delete rules are `.nullify` or `.cascade`, never `.deny`.
- No `@Attribute(.unique)`. The app enforces uniqueness in `LedgerBook`.
- Enums are stored as `String` raw values. Unknown values decode to a fallback (`AccountType.other`, `TransactionType.expense`, `TransactionStatus.cleared`, `CategoryKind.expense`).

## How to ship the next version

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

`Budget`, `ScheduledTemplate`, and `ExchangeRate` are new entities on their own tickets. Adding a new entity is its own schema version when those tickets land. `AccountFolder` (#43) is not reserved here, because a placeholder shape would itself need a migration once the real fields are known. An optional relationship added then can be a lightweight stage.

The domain type is `TransactionCategory`. The SwiftData class stays `CategoryRecord`, so the stored entity name is unchanged. Deleting a category does not update budgets yet. There is no budget entity in V1.
