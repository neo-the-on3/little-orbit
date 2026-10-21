import LittleOrbitFeatures
import SwiftUI

@main
struct LittleOrbitMacApp: App {
    /// Built once per launch by the composition root, here rather than in a view, then passed down.
    private let accounts: Result<AccountsFeature, any Error>

    init() {
        accounts = AppComposition.make()
    }

    var body: some Scene {
        WindowGroup {
            RootView(accounts: accounts)
        }
    }
}
