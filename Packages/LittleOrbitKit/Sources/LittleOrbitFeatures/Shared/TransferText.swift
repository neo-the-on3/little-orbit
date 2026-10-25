import Foundation

/// Transfer wording shared by the transaction rows (#23) and the Scheduled rows (#197 item 9).
enum TransferText {
    /// "received $12.00": the subtitle part on the sending side of a transfer between currencies (D17, D364).
    static func received(_ amount: String) -> String {
        FeatureText.format("received %@", amount)
    }
}
