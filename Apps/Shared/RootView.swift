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
                return AppFeatures(repository: repository)
            }
        }
    }

    /// The features the root view shows, wired over one repository.
    @MainActor
    struct AppFeatures {
        let accounts: AccountsFeature
        let transactions: TransactionsFeature

        init(repository: any LedgerRepository) {
            let transactionUseCases = TransactionUseCases(repository: repository)
            transactions = TransactionsFeature(useCases: transactionUseCases)
            // Account delete returns its change; the screens record it in the transactions' history (#93).
            accounts = AccountsFeature(useCases: AccountUseCases(repository: repository))
        }
    }

    /// Shows the Accounts home (iOS) or window (macOS) for what the composition root built.
    struct RootView: View {
        let features: Result<AppFeatures, any Error>

        var body: some View {
            switch features {
            case .success(let features):
                #if os(macOS)
                    AccountsSplitView(feature: features.accounts, transactions: features.transactions)
                #else
                    AccountsHomeView(feature: features.accounts, transactions: features.transactions)
                #endif
            case .failure(let error):
                ContentUnavailableView(
                    "Couldn't open your data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription),
                )
            }
        }
    }

    #Preview {
        RootView(features: .success(AppFeatures(repository: InMemoryLedgerRepository())))
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
