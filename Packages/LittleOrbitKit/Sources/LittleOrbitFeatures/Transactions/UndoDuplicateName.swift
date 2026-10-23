import Foundation
import LittleOrbitDomain

/// The name of a Duplicate step (D221): the existing shapes with "Duplicate", one whole phrase each in the
/// String Catalog. Duplicate acts on one row, and the copy stays in the original's account or accounts, so
/// there are no plural or "%lld Accounts" forms (D221.4). Refunds can't be duplicated (D221.2).
extension UndoActionTitle {
    /// "Duplicate Transaction in Household Card", or for a transfer "Duplicate Transfer from Household Card
    /// to Everyday Savings", or "Duplicate Transfer in Household Card" when only one of its accounts was read.
    static func duplicate(
        _ type: TransactionType,
        _ accounts: [Account],
        route: (source: Account, destination: Account)?,
    ) -> String {
        guard type == .transfer else {
            return FeatureText.format("Duplicate Transaction in %@", accounts[0].name)
        }
        if let route {
            return FeatureText.format(
                "Duplicate Transfer from %1$@ to %2$@",
                route.source.name,
                route.destination.name,
            )
        }
        return FeatureText.format("Duplicate Transfer in %@", accounts[0].name)
    }

    /// The short form, only when the step's accounts couldn't be read when it was recorded (D221.3).
    static func duplicate(_ type: TransactionType) -> String {
        if type == .transfer {
            FeatureText.string("Duplicate Transfer", comment: "Undo name: one transfer duplicated.")
        } else {
            FeatureText.string("Duplicate Transaction", comment: "Undo name: one transaction duplicated.")
        }
    }
}
