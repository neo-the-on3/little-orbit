import LittleOrbitCore
import LittleOrbitDomain
import LittleOrbitPersistence
import LittleOrbitTheme
import SwiftUI

#if os(iOS) || os(macOS)
    import LittleOrbitFeatures

    /// The composition root. It opens the store, then builds the repository, the use cases and the feature's
    /// view models, once per launch. The App structs call `make()` in their `init`, so SwiftUI re-creating a view
    /// never opens the store again. Views and view models only see the use-case protocols.
    @MainActor
    enum AppComposition {
        static func make() -> Result<AppFeatures, any Error> {
            Result { () throws -> AppFeatures in
                // Application Support/<bundle id>/LittleOrbit.store (or an App Group container when one is
                // configured), never default.store.
                let repository = try LittleOrbitStore.makeRepository(configuration: .appLocal())
                return try AppFeatures(repository: repository, backupStorage: FileBackupStorage.appDefault())
            }
        }

        /// Local backups (#40): one folder per backup in Application Support/<bundle id>/Backups on this device
        /// only, never in the App Group container (D195). Exports are Apple Archive files, and N and M are app
        /// settings in UserDefaults. App Lock (#29) replaces `AppLockOff` here when it lands.
        static func makeBackups(
            source: any LedgerBackupSource,
            storage: any BackupStorage,
            changes: LedgerChanges,
        ) -> BackupsViewModel {
            let service = BackupService(
                source: source,
                storage: storage,
                archiving: AppleArchiveBackupArchiving(),
                settings: UserDefaultsBackupSettings(),
                hashing: CryptoKitBackupHashing(),
                changes: changes,
                schemaVersion: LedgerSchemaVersion.description,
            )
            let useCases = BackupUseCases(
                service: service,
                authentication: AppLockOff(unlockMethod: DeviceUnlock.method),
            )
            return BackupsViewModel(
                useCases: useCases,
                presentation: BackupPresentation(device: DeviceUnlock.device),
                // VoiceOver hears when Back Up Now starts and finishes (D179.2).
                announce: { AccessibilityNotification.Announcement($0).post() },
            )
        }
    }

    /// The features the root view shows, wired over one repository.
    @MainActor
    struct AppFeatures {
        let accounts: AccountsFeature
        let transactions: TransactionsFeature
        let backups: BackupsViewModel

        init(repository: some LedgerRepository & LedgerBackupSource, backupStorage: any BackupStorage) {
            let transactionUseCases = TransactionUseCases(
                repository: repository,
                categoryNames: CatalogDefaultCategoryNames(),
            )
            // The default categories are seeded here, at launch, before any screen can write (D291.7, D293.4), and
            // nowhere else. A failed seed is only logged (D293.3): the app opens as normal and the next launch
            // tries again while the store is still empty.
            do {
                try transactionUseCases.seedDefaults?.seedIfFirstLaunch()
            } catch {
                StoreLog.failure(.defaultSeedFailed, error)
            }
            transactions = TransactionsFeature(useCases: transactionUseCases)
            // One signal for "the whole ledger was replaced" (a restore): the accounts reload, and every window's
            // undo history is cleared, so Undo never replays a step made against the old data (D187.2, N6).
            let changes = LedgerChanges()
            transactions.updates.follow(changes)
            // Account delete returns its change; the screens record it in the transactions' history (#93).
            accounts = AccountsFeature(useCases: AccountUseCases(repository: repository), ledgerChanges: changes)
            backups = AppComposition.makeBackups(source: repository, storage: backupStorage, changes: changes)
        }
    }

    /// Shows the Accounts home (iOS) or window (macOS) for what the composition root built.
    struct RootView: View {
        let features: Result<AppFeatures, any Error>
        /// Background time for the backup when the app goes to the background: the iOS app's UIKit adapter, `nil`
        /// on macOS, where the app isn't suspended.
        var backgroundActivity: (any BackgroundActivity)?
        @Environment(\.scenePhase) private var scenePhase
        #if os(iOS)
            @State private var isShowingSettings = false
        #endif

        var body: some View {
            switch features {
            case .success(let features):
                content(features)
                    // The automatic backup: at most once a day, at launch and when the app goes to the background
                    // (D62). It skips itself when nothing changed. In the background it runs inside a
                    // background-time assertion and is cancelled cleanly if the time runs out.
                    .task { await features.backups.backUpAutomaticallyIfNeeded() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background {
                            features.backups.backUpInBackground(backgroundActivity)
                        }
                    }
            case .failure(let error):
                ContentUnavailableView(
                    "Couldn't open your data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription),
                )
            }
        }

        @ViewBuilder
        private func content(_ features: AppFeatures) -> some View {
            #if os(macOS)
                AccountsSplitView(feature: features.accounts, transactions: features.transactions)
            #else
                AccountsHomeView(
                    feature: features.accounts,
                    transactions: features.transactions,
                    onShowSettings: { isShowingSettings = true },
                )
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView(backups: features.backups)
                }
            #endif
        }
    }

    #Preview {
        RootView(
            features: Result {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewBackups")
                return AppFeatures(
                    repository: InMemoryLedgerRepository(),
                    backupStorage: try FileBackupStorage(folder: folder),
                )
            }
        )
    }
#else
    /// watchOS stays a placeholder until its own issue; Accounts on the watch is out of scope for #22.
    struct RootView: View {
        var body: some View {
            VStack(spacing: Spacing.space3) {
                Text(LittleOrbitCore.placeholderTitle)
                    .font(.theme(Typography.WatchOS.title2))
                    .foregroundStyle(Color(ThemeColor.labelPrimary))
                Text("Placeholder")
                    .font(.theme(Typography.WatchOS.footnote))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
            }
            .padding(Spacing.space4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(ThemeColor.bgPrimary))
        }
    }

    #Preview {
        RootView()
    }
#endif
