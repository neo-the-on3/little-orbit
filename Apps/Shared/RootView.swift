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
                // One signal for "the whole ledger was replaced" (a restore), so every feature reloads.
                // Hook for #87: its app-wide undo history must also be cleared from this signal, so Undo can't replay
                // actions recorded against the pre-restore ledger. Whichever of #87 and #99 merges second wires it in.
                let changes = LedgerChanges()
                return AppFeatures(
                    accounts: AccountsFeature(
                        useCases: AccountUseCases(repository: repository),
                        ledgerChanges: changes,
                    ),
                    backups: try makeBackups(
                        source: repository,
                        storage: FileBackupStorage.appDefault(),
                        changes: changes,
                    ),
                )
            }
        }

        /// Local backups (#40): files in Application Support/<bundle id>/Backups on this device only, never in the
        /// App Group container. App Lock (#29) replaces `AppLockOff` here when it lands.
        static func makeBackups(
            source: any LedgerBackupSource,
            storage: any BackupStorage,
            changes: LedgerChanges,
        ) -> BackupsViewModel {
            let service = BackupService(
                source: source,
                storage: storage,
                cryptography: CryptoKitBackupCryptography(),
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

    /// What the composition root builds once per launch.
    @MainActor
    struct AppFeatures {
        let accounts: AccountsFeature
        let backups: BackupsViewModel
    }

    /// Shows the Accounts home (iOS) or window (macOS) for what the composition root built.
    struct RootView: View {
        let features: Result<AppFeatures, any Error>
        @Environment(\.scenePhase) private var scenePhase
        #if os(iOS)
            @State private var isShowingSettings = false
        #endif

        var body: some View {
            switch features {
            case .success(let features):
                content(features)
                    // The automatic backup: at most once a day, at launch and when the app goes to the background
                    // (D62). It skips itself when nothing changed.
                    .task { await features.backups.backUpAutomaticallyIfNeeded() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background {
                            Task { await features.backups.backUpAutomaticallyIfNeeded() }
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
                AccountsSplitView(feature: features.accounts)
            #else
                AccountsHomeView(feature: features.accounts, onShowSettings: { isShowingSettings = true })
                    .sheet(isPresented: $isShowingSettings) {
                        SettingsView(backups: features.backups)
                    }
            #endif
        }
    }

    #Preview {
        RootView(
            features: Result {
                let repository = InMemoryLedgerRepository()
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewBackups")
                let changes = LedgerChanges()
                return AppFeatures(
                    accounts: AccountsFeature(
                        useCases: AccountUseCases(repository: repository),
                        ledgerChanges: changes,
                    ),
                    backups: AppComposition.makeBackups(
                        source: repository,
                        storage: try FileBackupStorage(folder: folder),
                        changes: changes,
                    ),
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
