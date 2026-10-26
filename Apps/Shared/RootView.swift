// The iPhone and Mac root. The watch has its own (Apps/watchOS), with no ledger (D345).
#if os(iOS) || os(macOS)
    import LittleOrbitDomain
    import LittleOrbitFeatures
    import LittleOrbitPersistence
    import SwiftUI

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
                // The iPhone end of the watch link (#197 item 10). The Mac has no watch.
                #if os(iOS)
                    let watchLink: (any WatchCompanionLink)? = PhoneWatchSession()
                #else
                    let watchLink: (any WatchCompanionLink)? = nil
                #endif
                return try AppFeatures(
                    repository: repository,
                    backupStorage: FileBackupStorage.appDefault(),
                    watchLink: watchLink,
                )
            }
        }

        /// The iPhone side of the watch link (#197 item 10), or `nil` with no link (the Mac). Problems are logged with
        /// no user data.
        static func makeWatch(
            link: (any WatchCompanionLink)?,
            useCases: DefaultWatchPhoneUseCases?,
            updates: LedgerUpdates,
        ) -> WatchPhoneFeature? {
            guard let link, let useCases else {
                return nil
            }
            return WatchPhoneFeature(
                snapshots: useCases,
                requests: useCases,
                link: link,
                updates: updates,
                onProblem: { problem in
                    switch problem {
                    case .snapshotFailed(let error): StoreLog.failure(.watchSnapshotFailed, error)
                    case .publishFailed(let error): StoreLog.failure(.watchPublishFailed, error)
                    case .unreadableRequest: StoreLog.notice(.watchRequestUnreadable)
                    case .newerRequest: StoreLog.notice(.watchRequestNewer)
                    case .someNotApplied: StoreLog.notice(.watchRequestsNotApplied)
                    }
                },
            )
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
        let categories: CategoriesFeature
        let payees: PayeesFeature
        let scheduled: ScheduledFeature
        let importExport: ImportExportFeature
        /// The watch's Scheduled list and its Pay and Skip (#197 item 10); `nil` with no watch link (the Mac).
        let watch: WatchPhoneFeature?

        init(
            repository: some LedgerRepository & ScheduleRepository & LedgerBackupSource,
            backupStorage: any BackupStorage,
            watchLink: (any WatchCompanionLink)? = nil,
        ) {
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
            // The entry sheet's category picker reads and adds categories with the editor's use cases (#24).
            let editing = DefaultCategoryEditingUseCase(repository: repository)
            transactions = TransactionsFeature(
                useCases: transactionUseCases,
                categoryPicking: CategoryPickingUseCases(load: editing, edit: editing),
            )
            // One signal for "the whole ledger was replaced" (a restore): the accounts reload, and every window's
            // undo history is cleared, so Undo never replays a step made against the old data (D187.2, N6).
            let changes = LedgerChanges()
            transactions.updates.follow(changes)
            // Scheduled items (#26), over the device's clock and time zone, read on every call. Their due automatic
            // occurrences are recorded here, each once, before the accounts and the overdue badge are read (#26
            // QA), and again whenever the app becomes active.
            // The zone is the auto-updating one, so a zone change while the app runs is picked up (D21).
            let timeZone: @MainActor () -> TimeZone = { TimeZone.autoupdatingCurrent }
            var scheduledNow: @MainActor () -> Date = { Date() }
            #if DEBUG
                // D337.2: `-LittleOrbitScheduledToday 2026-11-20` moves today, and new items' creation day, for
                // scheduled items only. Not in release builds.
                if let day = ScheduledDebugClock.overriddenDay(in: ProcessInfo.processInfo.arguments) {
                    scheduledNow = ScheduledDebugClock.clock(
                        today: day,
                        launchedAt: Date(),
                        timeZone: timeZone,
                        now: { Date() },
                    )
                }
            #endif
            let scheduledUseCases = DefaultScheduledUseCases(
                repository: repository,
                now: scheduledNow,
                timeZone: timeZone,
            )
            // The watch reads a snapshot of the Scheduled list and sends Pay and Skip back; the iPhone applies them
            // through the same exactly-once path as its own Pay Now and Skip, outside undo history. No ledger or App
            // Group on the watch (D345).
            let watchUseCases = watchLink.map { _ in
                DefaultWatchPhoneUseCases(
                    repository: repository,
                    inbox: UserDefaultsWatchRequestInbox(),
                    today: { scheduledUseCases.today() },
                )
            }
            scheduled = ScheduledFeature(
                useCases: ScheduledScreenUseCases(
                    load: scheduledUseCases,
                    manage: scheduledUseCases,
                    catchUp: scheduledUseCases,
                    // The catch-up hint stays pending in app settings until Scheduled has shown it (D338.6).
                    notices: ScheduledCatchUpNotices(store: UserDefaultsScheduledCatchUpNotices()),
                ),
                updates: transactions.updates,
                onCatchUpProblem: { problem in
                    switch problem {
                    case .failed(let error): StoreLog.failure(.scheduledCatchUpFailed, error)
                    case .someNotRecorded: StoreLog.notice(.scheduledItemsNotRecorded)
                    case .createdAfterToday: StoreLog.notice(.scheduledItemsCreatedAfterToday)
                    }
                },
            )
            scheduled.catchUp(atLaunch: true)
            watch = AppComposition.makeWatch(link: watchLink, useCases: watchUseCases, updates: transactions.updates)
            watch?.start()
            // Account delete returns its change; the screens record it in the transactions' history (#93). Every
            // account change moves the shared store-change signal, so an open import re-plans (D327.1).
            accounts = AccountsFeature(
                useCases: AccountUseCases(repository: repository),
                plannedItems: scheduled,
                ledgerChanges: changes,
                updates: transactions.updates,
            )
            backups = AppComposition.makeBackups(source: repository, storage: backupStorage, changes: changes)
            // Settings › Categories and Payees (#24): the category and payee use cases, the category editor's
            // reads and saves, and the payee list's reads.
            let categoryUseCases = CategoryUseCases(repository: repository)
            categories = CategoriesFeature(
                useCases: CategoryScreenUseCases(
                    load: editing,
                    edit: editing,
                    categories: categoryUseCases,
                ),
                updates: transactions.updates,
            )
            payees = PayeesFeature(
                useCases: PayeeScreenUseCases(
                    load: DefaultLoadPayeesUseCase(repository: repository),
                    manage: categoryUseCases.managePayees,
                ),
                updates: transactions.updates,
            )
            // CSV import and export (#30), with the Debit & Credit preset (#60). An import or Undo Import reloads
            // every window, like a transaction change.
            importExport = ImportExportFeature(
                useCases: ImportExportUseCases(
                    importing: ImportUseCases(
                        repository: repository,
                        formats: ImportFormats(specific: [DebitAndCreditFormat()]),
                    ),
                    exporting: DefaultExportTransactionsUseCase(repository: repository),
                ),
                updates: transactions.updates,
            )
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
            /// The undo history of the window Settings was opened from (D287.4).
            @State private var settingsUndoHistory: WindowUndoHistory?
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
                        // A day may have passed, or the clock or time zone changed, while the app was away.
                        if phase == .active {
                            features.scheduled.catchUp(atLaunch: false)
                            // A request whose save failed is tried again, and the watch gets today's list.
                            features.watch?.start()
                        }
                        if phase == .background {
                            features.backups.backUpInBackground(backgroundActivity)
                        }
                    }
                    // Every ledger change, from any window or the watch, sends the watch a new snapshot.
                    .onChange(of: features.scheduled.revision) { features.watch?.publish() }
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
                AccountsSplitView(
                    feature: features.accounts,
                    transactions: features.transactions,
                    scheduled: features.scheduled,
                )
                // File › Import CSV from Files… and Export Transactions to CSV… open here, in the front window.
                .importExport(features.importExport)
            #else
                AccountsHomeView(
                    feature: features.accounts,
                    transactions: features.transactions,
                    scheduled: features.scheduled,
                    onShowSettings: { history in
                        settingsUndoHistory = history
                        isShowingSettings = true
                    },
                )
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView(
                        backups: features.backups,
                        categories: features.categories,
                        payees: features.payees,
                        importExport: features.importExport,
                        onCategoryRemoval: { settingsUndoHistory?.clearAfterRemoval() },
                    )
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
#endif
