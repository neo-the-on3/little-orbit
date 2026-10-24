#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import Foundation

    /// The state for the transaction entry sheet. Its view model is made once, when the sheet is requested.
    struct TransactionFormSheet: Identifiable {
        let id = UUID()
        let model: TransactionFormViewModel
    }

    /// The refund sheet for one expense, iOS and macOS ⌘R (D65), with its view model made when it's requested.
    struct RefundSheet: Identifiable {
        let id = UUID()
        let model: RefundFormViewModel
    }

    /// The macOS bulk edit sheet, with its view model made when the sheet is requested.
    struct BulkEditSheet: Identifiable {
        let id = UUID()
        let model: BulkEditViewModel
    }
#endif
