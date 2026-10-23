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

- `<group container>/LittleOrbit.store`, shared with the app's extensions, when the app's Info.plist sets `LittleOrbitAppGroupIdentifier` and the app is signed with that App Group entitlement, or
- `Application Support/<bundle id>/LittleOrbit.store`, private to the app.

Which one is decided by the store-home rule in [App Group](#app-group-52) below. `StoreLocation.resolve` returns the URL and which location it chose, with the fallback reason: `noAppGroupConfigured` or `notEntitled` (properties of the build), `containerUnavailable` (entitled, but the container is missing or not writable and no group store is recorded) or `awaitingMigration` (entitled, but the store is already in the app folder until #102 moves it). The app logs that choice once per launch (subsystem: the bundle ID, category `Store`), with the reason only and never a path or user data. The container lookup (`AppGroupContainerLookup`), the entitlement check (`AppGroupEntitlementCheck`), the marker (`StoreHomeMarkerStore`) and the "holds data" check (`StoreContentsCheck`) are injectable, so every branch is unit-tested on Linux. On macOS, `containerURL(forSecurityApplicationGroupIdentifier:)` returns a URL even when the app isn't entitled to the group (iOS returns `nil`), so the entitlement is read from the app's own signature there. iOS has no API to read it, but its lookup returns `nil` exactly when the app isn't entitled, so on iOS a missing container is reported as `notEntitled` and falls back (`AppGroupEntitlementCheck.containerPresence`). `LittleOrbitStore.makeContainer` refuses any other sync mode and passes SwiftData's local-only database option. There is no CloudKit container, entitlement, or identifier in this package. Sync is a later change; the schema is shaped so that change does not have to rewrite V1.

### App Group (#52)

The group ID is set once, as `LITTLEORBIT_APP_GROUP_IDENTIFIER` in `Config/Shared.xcconfig` (`group.app.littleorbit` by default, D34.1). It follows the bundle ID base (`group.$(LITTLEORBIT_BUNDLE_ID_BASE)$(LITTLEORBIT_BUNDLE_ID_SUFFIX)`), and a builder can override it in the gitignored `Config/Local.xcconfig`. The app never reads xcconfig values directly. The iOS and macOS targets generate their Info.plist and merge `Config/LittleOrbit-Info.plist`, which writes that setting into `LittleOrbitAppGroupIdentifier`. `Config/LittleOrbit.entitlements` holds the matching `com.apple.security.application-groups` entry, but the iOS and macOS targets take `CODE_SIGN_ENTITLEMENTS` from `LITTLEORBIT_ENTITLEMENTS`, which `Shared.xcconfig` leaves empty (a builder can set it in `Local.xcconfig`): enabling it needs signed simulator builds and App Group registration (D154, #84). Until then the apps aren't entitled, and every build on iOS and macOS uses the Application Support fallback and logs `notEntitled`.

#### Store-home rule

The app remembers where its store lives, so a store only moves through #102's one-time migration and never because of one bad launch (agreed on #98, after Kiran asked that the app use the App Group when it's available and fall back to the app folder when it isn't).

- **Marker.** `Application Support/<bundle id>/StoreHome.json`, written atomically. It records the kind (`group` or `appFolder`), the exact group ID when the kind is `group`, and the store's ID: a UUID kept beside the store file in `LittleOrbit.store.id`, created on the first writable open (SwiftData has no public store metadata, and a file beside the store moves with it). The store ID is for #102 and diagnostics; the decision doesn't use it. If the ID file can't be read, a new UUID replaces it and the marker line logs `store ID replacedUnreadable`, so the change of identity leaves a trace. #102 and the backups must copy or skip `LittleOrbit.store.id` explicitly, along with `-wal` and `-shm`.
- **When it's written.** `LittleOrbitStore.makeContainer` writes it right after a writable store opens, before any user write, and only when it changes (`StoreHomeRecorder`). A failed write is logged by reason and the launch goes on; the next launch tries again. A best-effort copy goes to `<group container>/StoreHome.json` whenever the container was reachable.
- **Disk as well as the marker.** "Holds data" means the store has an account or a transaction, as for backups (D179.3); seeded categories alone don't count. On Apple platforms the check (`StoreContentsProbe`) never opens the store itself: it copies the store file and any `-wal` and `-shm` files to a scratch folder, opens the copy read-only with the current schema and no migration plan, counts, and deletes the copy. So it can't migrate the store, create sidecar files or change anything, and tests compare the store folder's bytes and listing before and after. A copy that can't be opened with the current schema (an older version, or a file that isn't a store) counts as holding data, so it is never left behind.
- **Never a torn copy.** The store and `-wal` are fingerprinted (file number, size, modification date) before and after the copy. If either changed, as a second writer's checkpoint would make it, the copy is retried once; a second change counts as holding data. A copy that fails, a change during both attempts, or a copy that can't be opened is logged as `Store contents check counted as holding data (reason: copyFailed | changedDuringCopy | openFailed)`, so a `storesInBothLocations` that comes from a failed check can be told apart from a real conflict. Each probe first removes `littleorbit-store-probe-*` scratch folders older than five minutes left by a crashed probe (newer ones may belong to a probe still running). The prefix names the app because the unsandboxed Mac app shares its temporary folder with the user's other apps; the sweep matches only that prefix, so another app's folders are never touched. On Darwin the probe is wrapped in an `OSSignposter` interval named `StoreContentsProbe` (category `Store`) for timing runs on large ledgers.
- **Probed only when it matters.** A store file that doesn't exist holds no data and isn't probed. Marker=`group` probes nothing. Marker=`appFolder` probes nothing unless a group store file exists, then probes the group store first and the app-folder store only if the group store holds data. With no marker, the group store is probed first and each store only if its file exists. Rows 3 to 7 probe nothing. So the steady state before #102 (marker=`appFolder`, no group store file) costs one file-existence check per launch. On Linux, `StoreContentsCheck.fileHasBytes` stands in for it; Linux builds no app, so that check is test-only.
- **Repairs are logged.** When a launch rewrites the marker from what's on disk instead of following it, the location line ends with `(marker repaired: <reason>)`: `appFolderEmptyGroupHasData` (marker=`appFolder`, the app folder is empty and the group store holds data), `noMarkerGroupHasData`, `noMarkerAppFolderHasData`, or `unreadableMarker`. A build without the entitlement can't tell an unreadable marker from no marker, so it uses the app folder (row 7) and rewrites the marker as `appFolder`, logged as `unreadableMarker`.

| # | Build and container | Marker and disk | Result |
|---|---|---|---|
| 1 | Entitled, container usable | No marker, or marker=`group` with the same ID | The group store, and marker=`group` is written or repaired. With no group marker and an app-folder store that holds data, row 2 applies instead. |
| 2 | Entitled, container usable | Marker=`appFolder`, or the app-folder store holds data | The app folder (`awaitingMigration`) until #102 migrates. Both stores holding data throws `StoreError.storesInBothLocations`, routed to #102, never a merge. If only the group store holds data and the app folder is empty, the group store is used and the marker repaired, since nothing would be split. |
| 3 | Entitled, container missing or not writable | No marker, or marker=`appFolder` | The app folder (`containerUnavailable`), and marker=`appFolder`. |
| 4 | Entitled, container missing or not writable | Marker=`group`, or a marker that can't be read | Throws `StoreError.appGroupContainerUnavailable` (`noContainer`, `containerNotWritable`). No empty store is created. |
| 5 | Not entitled, or no group configured | Marker=`group` | Throws `StoreError.storeIsInAppGroup` (`notEntitled`, `noAppGroupConfigured`). Never a silent fallback. |
| 6 | Any | The marker's group ID differs from the configured one, for example after a builder override | Throws `StoreError.storeIsInAppGroup(.groupIdentifierChanged)`. Never a silent switch. |
| 7 | Not entitled, or no group configured | Anything else | The app folder (`notEntitled`, `noAppGroupConfigured`), as before. |

So a container that comes and goes across launches keeps the store in the app folder once it has fallen back there. If a fallback store gets data and the container then comes back with a group store that also holds data, the app shows the `storesInBothLocations` error and changes neither store.

Rows 4 and 5 (with 6) follow the recommendation in the open questions to Kiran on #98: an error, no empty store, and no "start a new empty store" choice. Today that error is the app's existing store-failure screen, which shows the error's system description and has no Try Again. The error copy for `appGroupContainerUnavailable`, `storeIsInAppGroup` and `storesInBothLocations`, and Try Again where Kiran's answer to (A) asks for it, come from Product Manager via #120 before the entitlement is turned on.

On iOS, (A) and (C) look the same at run time. iOS reports the entitlement through the container lookup, so "entitled but no container" never happens there: a missing container is `notEntitled`, which is row 7 with no marker and row 5 (`storeIsInAppGroup(.notEntitled)`) with marker=`group`. Row 4 can only happen on iOS as `containerNotWritable`. Kiran's answer to (C) therefore also decides (A) on iOS. On macOS the two stay distinct, because the entitlement is read from the signature.

The app-folder location isn't only a development fallback: per D183 the app may ship without the App Group entitlement (for example without an Apple account), so `Application Support/<bundle id>` is a supported shipping location. The move from the app folder into the group container is #102, not this rule.

#### Extensions

An extension opens the app's store with `StoreConfiguration.sharedReadOnly()`: the group container only, with SwiftData's `allowsSave` off. It follows the same rule read-only and never creates a file or folder. It never falls back, because an extension's own Application Support has no data, and it never decides the location itself: it throws `StoreError.sharedStoreUnavailable` when the build names no group or isn't entitled to it, `StoreError.appGroupContainerUnavailable` when the system returns no container, and `StoreError.sharedStoreNotInGroup` when the store-home copy in the group is missing or stale (it says `appFolder` or names another group), which the extension treats as no data. A read-only store can't create or migrate its file, so an extension that runs before the app has ever created the store throws `StoreError.readOnlyStoreMissing` and leaves no file behind. After a schema change, an extension that runs before the updated app has migrated the store must also fail cleanly and never migrate; #38 and #39 cover that once there is a second schema version.

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
