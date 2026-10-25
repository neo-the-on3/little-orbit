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
                    let watchLink: (any WatchCompanionLink)? = PhoneWatchSession.makeLink()
                #else
                    let watchLink: (any WatchCompanionLink)? = nil
                #endif
                let features = try AppFeatures(
                    repository: repository,
                    backupStorage: FileBackupStorage.appDefault(),
                    watchLink: watchLink,
                )
                #if DEBUG
                    // `-LittleOrbitDeleteScheduledItemName <name> -LittleOrbitDeleteScheduledItemAfter <seconds>`
                    // deletes that item later, as another window would (#258 testing). Not in release builds.
                    features.scheduled.startLaunchDelete()
                #endif
                return features
            }
        }

        /// The watch's Pay and Skip use cases over the iPhone's ledger and its request inbox in app settings
        /// (#197 item 10), or `nil` with no watch link (the Mac).
        static func makeWatchUseCases(
            link: (any WatchCompanionLink)?,
            repository: some LedgerRepository & ScheduleRepository & LedgerBackupSource,
            today: @escaping @MainActor () -> CalendarDay,
        ) -> DefaultWatchPhoneUseCases? {
            link.map { _ in
                let inbox = UserDefaultsWatchRequestInbox()
                #if DEBUG
                    // Testing hook: `-LittleOrbitWatchNotices refused-pay|refused-skip|mixed|refused-group` seeds
                    // notices against existing items, so the real card shows (UI Designer 6407485986).
                    // Seeding must run here, before `WatchRequestNoticeViewModel` is created in `AppFeatures.init`:
                    // the model reads the store when it's made, so seeding later would leave the card empty until
                    // the next reload.
                    WatchNoticesLaunchPreset.seed(repository: repository, inbox: inbox)
                #endif
                return DefaultWatchPhoneUseCases(
                    repository: repository,
                    inbox: inbox,
                    today: today,
                )
            }
        }

        /// The iPhone side of the watch link (#197 item 10), or `nil` with no link (the Mac). Problems are logged with
        /// no user data.
        static func makeWatch(
            link: (any WatchCompanionLink)?,
            useCases: DefaultWatchPhoneUseCases?,
            notices: WatchRequestNoticeViewModel?,
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
                notices: notices,
                onProblem: { problem in
                    switch problem {
                    case .snapshotFailed(let error): StoreLog.failure(.watchSnapshotFailed, error)
                    case .publishFailed(let error): StoreLog.failure(.watchPublishFailed, error)
                    case .unreadableRequest: StoreLog.notice(.watchRequestUnreadable)
                    case .newerRequest: StoreLog.notice(.watchRequestNewer)
                    case .someNotApplied: StoreLog.notice(.watchRequestsNotApplied)
                    case .someRefused: StoreLog.notice(.watchRequestsRefused)
                    }
                },
            )
        }

        /// The 'Notify when due' reminder use cases (#26, D340.7) over `notifications`, worded in the privacy version,
        /// at the Reminder Time kept in app settings.
        static func makeReminderUseCases(
            repository: any ScheduleRepository,
            notifications: any ScheduledNotificationScheduling,
            now: @escaping @MainActor () -> Date,
            timeZone: @escaping @MainActor () -> TimeZone,
        ) -> DefaultScheduledReminderUseCases {
            var notifications = notifications
            #if DEBUG
                // `-LittleOrbitNotificationsAuthorized YES` treats notification permission as granted, with no
                // system prompt, so reminders schedule on a simulator. Adds and removals still reach the system
                // center. Not in release builds.
                notifications = NotificationsAuthorizedOverride.applying(
                    to: notifications,
                    arguments: ProcessInfo.processInfo.arguments,
                )
            #endif
            return DefaultScheduledReminderUseCases(
                repository: repository,
                notifications: notifications,
                times: UserDefaultsScheduledReminderTime(),
                wording: ScheduledReminderComposer(),
                now: now,
                timeZone: timeZone,
            )
        }

        /// Keeps the pending reminders current (D340.7). A failed reschedule is logged with no user data. A reminder
        /// arriving while the app is open refills the shared budget, since the nearest one has gone.
        static func makeReminders(
            useCases: DefaultScheduledReminderUseCases,
            notifications: UserNotificationScheduling,
        ) -> ScheduledReminders {
            let reminders = ScheduledReminders(useCase: useCases) { error in
                StoreLog.failure(.scheduledRemindersNotUpdated, error)
            }
            notifications.onReminderDelivered = { [weak reminders] in reminders?.refresh() }
            return reminders
        }

        /// The clock scheduled items read: the device's. In Debug builds, `-LittleOrbitScheduledToday 2026-11-20` moves
        /// today, and new items' creation day, for scheduled items only (D337.2). Not in release builds.
        static func makeScheduledClock(timeZone: @escaping @MainActor () -> TimeZone) -> @MainActor () -> Date {
            #if DEBUG
                if let day = ScheduledDebugClock.overriddenDay(in: ProcessInfo.processInfo.arguments) {
                    return ScheduledDebugClock.clock(
                        today: day,
                        launchedAt: Date(),
                        timeZone: timeZone,
                        now: { Date() },
                    )
                }
            #endif
            return { Date() }
        }

        /// Tapping a reminder opens its item in one window, which takes the tap once its navigation is up (S33): on
        /// iOS the scene the system sent it to, on the Mac the main window brought to the front.
        static func routeReminderTaps(from notifications: UserNotificationScheduling, to taps: ScheduledReminderTaps) {
            notifications.onOpenItem = { [taps] itemID, scene in
                #if os(macOS)
                    let window = UserNotificationScheduling.bringMainWindowForward(among: taps.windows)
                    taps.tapped(itemID: itemID, window: window)
                #else
                    taps.tapped(itemID: itemID, window: scene)
                #endif
            }
        }

        /// The transactions feature over `repository`. The default categories are seeded here, at launch, before any
        /// screen can write (D291.7, D293.4), and nowhere else. A failed seed is only logged (D293.3): the app opens
        /// as normal and the next launch tries again while the store is still empty. An account's history also shows
        /// its scheduled occurrences as Upcoming rows (S85), unless Show upcoming is off (D348).
        static func makeTransactions(
            repository: some LedgerRepository & ScheduleRepository,
            editing: DefaultCategoryEditingUseCase,
            showUpcoming: UserDefaultsShowUpcomingSetting,
        ) -> TransactionsFeature {
            let transactionUseCases = TransactionUseCases(
                repository: repository,
                categoryNames: CatalogDefaultCategoryNames(),
                // Undo and Redo of a Scheduled form save go through the schedule (D351.1).
                schedule: repository,
            )
            do {
                try transactionUseCases.seedDefaults?.seedIfFirstLaunch()
            } catch {
                StoreLog.failure(.defaultSeedFailed, error)
            }
            return TransactionsFeature(
                useCases: transactionUseCases.showingScheduled(
                    from: repository,
                    while: { showUpcoming.showsUpcoming },
                ),
                categoryPicking: CategoryPickingUseCases(load: editing, edit: editing),
            )
        }

        /// Local backups (#40): one folder per backup in Application Support/<bundle id>/Backups on this device
        /// only, never in the App Group container (D195). Exports are Apple Archive files, and N and M are app
        /// settings in UserDefaults. App Lock (#29) replaces `AppLockOff` here when it lands. Each backup carries the
        /// shared settings (D96.1), which today is Show upcoming (D348).
        static func makeBackups(
            source: any LedgerBackupSource,
            storage: any BackupStorage,
            changes: LedgerChanges,
            sharedSettings: any BackupSharedSettingsStore,
        ) -> BackupsViewModel {
            let service = BackupService(
                source: source,
                storage: storage,
                archiving: AppleArchiveBackupArchiving(),
                settings: UserDefaultsBackupSettings(),
                hashing: CryptoKitBackupHashing(),
                changes: changes,
                schemaVersion: LedgerSchemaVersion.description,
                sharedSettings: sharedSettings,
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
        let scheduledUpcoming: ScheduledUpcomingSettingsModel

        init(
            repository: some LedgerRepository & ScheduleRepository & LedgerBackupSource,
            backupStorage: any BackupStorage,
            watchLink: (any WatchCompanionLink)? = nil,
        ) {
            // The entry sheet's category picker reads and adds categories with the editor's use cases (#24).
            let editing = DefaultCategoryEditingUseCase(repository: repository)
            // Settings › Scheduled Items › Show upcoming, in app settings (D348).
            let showUpcoming = UserDefaultsShowUpcomingSetting()
            // Seeds the default categories first, before any screen can write.
            transactions = AppComposition.makeTransactions(
                repository: repository,
                editing: editing,
                showUpcoming: showUpcoming,
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
            let scheduledNow = AppComposition.makeScheduledClock(timeZone: timeZone)
            let scheduledUseCases = DefaultScheduledUseCases(
                repository: repository,
                now: scheduledNow,
                timeZone: timeZone,
            )
            // The watch reads a snapshot of the Scheduled list and sends Pay and Skip back; the iPhone applies them
            // through the same exactly-once path as its own Pay Now and Skip, outside undo history. No ledger or App
            // Group on the watch (D345). A request it can't apply leaves a card on the Scheduled list (D374, D376).
            let watchUseCases = AppComposition.makeWatchUseCases(
                link: watchLink,
                repository: repository,
                today: { scheduledUseCases.today() },
            )
            let watchNotices = watchUseCases.map { WatchRequestNoticeViewModel(useCases: $0) }
            // 'Notify when due' reminders (#26, D340.7): local notifications through the system center, worded in
            // the privacy version, at the Reminder Time kept in app settings. Rescheduled after catch-up, at launch
            // and on activation, and after every change.
            // Made here, at launch, so it's the notification center's delegate before launch ends and a tap from a
            // cold launch reaches it (S33).
            let notifications = UserNotificationScheduling()
            let reminderUseCases = AppComposition.makeReminderUseCases(
                repository: repository,
                notifications: notifications,
                now: scheduledNow,
                timeZone: timeZone,
            )
            let reminders = AppComposition.makeReminders(useCases: reminderUseCases, notifications: notifications)
            scheduled = ScheduledFeature(
                useCases: ScheduledScreenUseCases(
                    load: scheduledUseCases,
                    manage: scheduledUseCases,
                    catchUp: scheduledUseCases,
                    // The catch-up hint stays pending in app settings until Scheduled has shown it (D338.6).
                    notices: ScheduledCatchUpNotices(store: UserDefaultsScheduledCatchUpNotices()),
                    permission: reminderUseCases,
                    reminderTime: reminderUseCases,
                ),
                updates: transactions.updates,
                reminders: reminders,
                watchNotices: watchNotices,
                onCatchUpProblem: { problem in
                    switch problem {
                    case .failed(let error): StoreLog.failure(.scheduledCatchUpFailed, error)
                    case .someNotRecorded: StoreLog.notice(.scheduledItemsNotRecorded)
                    case .createdAfterToday: StoreLog.notice(.scheduledItemsCreatedAfterToday)
                    }
                },
            )
            AppComposition.routeReminderTaps(from: notifications, to: scheduled.reminderTaps)
            scheduled.catchUp(atLaunch: true)
            watch = AppComposition.makeWatch(
                link: watchLink,
                useCases: watchUseCases,
                notices: watchNotices,
                updates: transactions.updates,
            )
            watch?.start()
            scheduledUpcoming = ScheduledUpcomingSettingsModel(store: showUpcoming, updates: transactions.updates)
            // Account delete returns its change; the screens record it in the transactions' history (#93). Every
            // account change moves the shared store-change signal, so an open import re-plans (D327.1).
            accounts = AccountsFeature(
                useCases: AccountUseCases(repository: repository),
                plannedItems: scheduled,
                ledgerChanges: changes,
                updates: transactions.updates,
            )
            // Show upcoming is a shared preference, so it goes in every backup and a restore puts it back (D348.3).
            backups = AppComposition.makeBackups(
                source: repository,
                storage: backupStorage,
                changes: changes,
                sharedSettings: ShowUpcomingBackupSettings(store: showUpcoming),
            )
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
        /// This window's open sheets, which a tapped reminder asks before it navigates (S33).
        @State private var openSheets = OpenSheets()
        #if os(macOS)
            @Environment(\.openWindow) private var openWindow
        #endif
        #if os(iOS)
            @State private var isShowingSettings = false
            /// The undo history of the window Settings was opened from (D287.4).
            @State private var settingsUndoHistory: WindowUndoHistory?
        #endif

        var body: some View {
            switch features {
            case .success(let features):
                content(features)
                    .environment(openSheets)
                    #if os(macOS)
                        // A tapped reminder opens a new main window when none is open (UI Designer 6402418696).
                        .onAppear {
                            UserNotificationScheduling.openMainWindow = { [openWindow] in
                                openWindow(id: UserNotificationScheduling.mainWindowID)
                            }
                        }
                    #endif
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
                        scheduled: features.scheduled,
                        scheduledUpcoming: features.scheduledUpcoming,
                        onCategoryRemoval: { settingsUndoHistory?.clearAfterRemoval() },
                    )
                    // Settings holds nothing unsaved itself, so a tapped reminder closes it first, unless a sheet
                    // over it has unsaved edits (S33, UI Designer 6402418696).
                    .openSheet(hasUnsavedEdits: { false }, close: { isShowingSettings = false })
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
