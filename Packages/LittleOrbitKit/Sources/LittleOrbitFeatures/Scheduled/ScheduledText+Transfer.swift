import Foundation

/// A scheduled transfer between currencies (#197 item 9, #23 "Transfer/Cross-currency – sent and received,
/// read-only rate" and "Transfer sheet – cross-currency, read-only rate").
extension ScheduledText {
    static var received: String {
        FeatureText.string(
            "Received",
            comment: "Scheduled transfer form field, and item screen row: the amount that arrives in To’s currency.",
        )
    }

    /// "1 USD = ₹83.33 · worked out from the two amounts": the read-only rate (D17).
    static func rate(_ destinationCode: String, _ sourceAmount: String) -> String {
        FeatureText.format("1 %1$@ = %2$@ · worked out from the two amounts", destinationCode, sourceAmount)
    }

    /// "Enter the amount received in USD." (#23)
    static func enterReceived(_ currencyCode: String) -> String {
        FeatureText.format("Enter the amount received in %@.", currencyCode)
    }
}
