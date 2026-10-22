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

1. If the app's Info.plist sets `LittleOrbitAppGroupIdentifier`, the app is signed with that App Group entitlement and the group container's folder can be created, the store is `<group container>/LittleOrbit.store`, shared with the app's extensions.
2. If no group is set or the app isn't signed with its entitlement, it is `Application Support/<bundle id>/LittleOrbit.store`.
3. If the app is entitled but the system returns no container, or the container's folder can't be created, opening the store throws `StoreError.appGroupContainerUnavailable` (`noContainer`, `containerNotWritable`) and the app shows its store-failure screen. It never falls back then: those are runtime failures, and one bad launch would otherwise open a second, empty store that the next good launch leaves behind.

`StoreLocation.resolve` returns the URL and which location it chose, with the fallback reason (`noAppGroupConfigured` or `notEntitled`, both properties of the build). The app logs that choice once per launch (subsystem: the bundle ID, category `Store`). The container lookup (`AppGroupContainerLookup`) and the entitlement check (`AppGroupEntitlementCheck`) are injectable, so every branch is unit-tested on Linux. On macOS, `containerURL(forSecurityApplicationGroupIdentifier:)` returns a URL even when the app isn't entitled to the group (iOS returns `nil`), so the entitlement is read from the app's own signature there. iOS has no API to read it, but its lookup returns `nil` exactly when the app isn't entitled, so on iOS a missing container is reported as `notEntitled` and falls back (`AppGroupEntitlementCheck.containerPresence`). `LittleOrbitStore.makeContainer` refuses any other sync mode and passes SwiftData's local-only database option. There is no CloudKit container, entitlement, or identifier in this package. Sync is a later change; the schema is shaped so that change does not have to rewrite V1.

### App Group (#52)

The group ID is set once, as `LITTLEORBIT_APP_GROUP_IDENTIFIER` in `Config/Shared.xcconfig` (`group.app.littleorbit` by default, D34.1). It follows the bundle ID base (`group.$(LITTLEORBIT_BUNDLE_ID_BASE)$(LITTLEORBIT_BUNDLE_ID_SUFFIX)`), and a builder can override it in the gitignored `Config/Local.xcconfig`. The app never reads xcconfig values directly. The iOS and macOS targets generate their Info.plist and merge `Config/LittleOrbit-Info.plist`, which writes that setting into `LittleOrbitAppGroupIdentifier`. `Config/LittleOrbit.entitlements` holds the matching `com.apple.security.application-groups` entry, but the iOS and macOS targets take `CODE_SIGN_ENTITLEMENTS` from `LITTLEORBIT_ENTITLEMENTS`, which `Shared.xcconfig` leaves empty (a builder can set it in `Local.xcconfig`): enabling it needs signed simulator builds and App Group registration (D154, #84). Until then the apps aren't entitled, and every build on iOS and macOS uses the Application Support fallback and logs `notEntitled`.

Nothing is migrated between the two locations (D34.2). A dev store in Application Support is left in place, and the first launch with the entitlement starts with an empty store in the group container. The choice depends only on the build, so a build never switches location between launches.

An extension opens the app's store with `StoreConfiguration.sharedReadOnly()`: the group container only, with SwiftData's `allowsSave` off. It never falls back, because an extension's own Application Support has no data: it throws `StoreError.sharedStoreUnavailable` when the build names no group or isn't entitled to it, and `StoreError.appGroupContainerUnavailable` when the container can't be used. A read-only store can't create or migrate its file, so an extension that runs before the app has ever created the store throws `StoreError.readOnlyStoreMissing` and leaves no file behind. After a schema change, an extension that runs before the updated app has migrated the store must also fail cleanly and never migrate; #38 and #39 cover that once there is a second schema version.

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
