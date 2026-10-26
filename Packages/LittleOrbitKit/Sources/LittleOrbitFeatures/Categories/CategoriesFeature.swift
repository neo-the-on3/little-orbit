import Foundation
import LittleOrbitDomain

/// Everything the category screens need (#24), built once by the composition root from the injected use
/// cases. Each Settings window makes its own screen model.
@MainActor
public final class CategoriesFeature {
    public let useCases: CategoryScreenUseCases
    private let updates: LedgerUpdates?

    /// `updates` tells every window to reload after a category change, as a transaction change does (D187.4).
    public init(useCases: CategoryScreenUseCases, updates: LedgerUpdates? = nil) {
        self.useCases = useCases
        self.updates = updates
    }

    /// Moves on after every change to the shared store, from any window or a restore. An open screen reloads
    /// on it, so it never shows a category another window has removed or changed (D187.4).
    public var revision: Int {
        updates?.revision ?? 0
    }

    public func makeScreen() -> CategoriesViewModel {
        CategoriesViewModel(useCases: useCases) { [weak updates] in updates?.changed() }
    }
}
