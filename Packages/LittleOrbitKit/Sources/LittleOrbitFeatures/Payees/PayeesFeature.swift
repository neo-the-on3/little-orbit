import Foundation
import LittleOrbitDomain

/// The use cases the payee screens need, from the composition root.
@MainActor
public struct PayeeScreenUseCases {
    public var load: any LoadPayeesUseCase
    public var manage: any ManagePayeesUseCase

    public init(load: any LoadPayeesUseCase, manage: any ManagePayeesUseCase) {
        self.load = load
        self.manage = manage
    }
}

/// Everything the payee screens need (#24), built once by the composition root from the injected use cases.
/// Each Settings window makes its own screen model.
@MainActor
public final class PayeesFeature {
    public let useCases: PayeeScreenUseCases
    private let updates: LedgerUpdates?

    /// `updates` tells every window to reload after a payee change, as a transaction change does (D187.4).
    public init(useCases: PayeeScreenUseCases, updates: LedgerUpdates? = nil) {
        self.useCases = useCases
        self.updates = updates
    }

    /// Moves on after every change to the shared store, from any window or a restore. An open screen reloads
    /// on it, so it never shows a payee another window has removed or changed (D187.4).
    public var revision: Int {
        updates?.revision ?? 0
    }

    public func makeScreen() -> PayeesViewModel {
        PayeesViewModel(useCases: useCases) { [weak updates] in updates?.changed() }
    }
}
