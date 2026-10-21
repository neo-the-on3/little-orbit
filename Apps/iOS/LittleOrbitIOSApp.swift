import SwiftUI

@main
struct LittleOrbitIOSApp: App {
    /// Built once per launch by the composition root, here rather than in a view, then passed down.
    private let features: Result<AppFeatures, any Error>

    init() {
        features = AppComposition.make()
    }

    var body: some Scene {
        WindowGroup {
            RootView(features: features)
        }
    }
}
