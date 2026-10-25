import Foundation
import LittleOrbitDomain

/// Pay with Custom Date or Amount (D24) on the Scheduled screens.
extension ScheduledListViewModel {
    /// Opens Pay with Custom Date or Amount for a due occurrence.
    public func openCustomPay(_ row: ScheduledRow) {
        guard let occurrence = row.occurrence, let item = listing.item(row.itemID) else {
            return
        }
        payment = ScheduledPayViewModel(
            useCases: useCases,
            listing: listing,
            item: item,
            occurrence: occurrence,
            locale: locale,
        ) { [weak self] change in
            self?.payment = nil
            if let change {
                self?.recordSettlement(change)
            }
            self?.load()
            self?.changed()
        }
    }

    /// The item screen's button and the row menu item: one entry per platform, with the Mac's ellipsis, as it opens
    /// a sheet (D190, D334.10).
    public var payCustomTitle: String {
        platform == .macOS ? ScheduledText.payCustomMac : ScheduledText.payCustom
    }
}
