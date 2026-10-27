#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// The header's styles, apart from the view so AccountDetailView.swift stays under its length limit (m7).
    extension AccountDetailView {
        static func balanceLabel(_ row: AccountRowModel) -> String {
            #if os(macOS)
                row.detailCaption
            #else
                "Current balance"
            #endif
        }

        #if os(macOS)
            static let captionStyle = Typography.MacOS.footnote
            static let amountStyle = Typography.Amount.macOSTitle
            static let headerAlignment = HorizontalAlignment.leading
            static let headerFrameAlignment = Alignment.leading
        #else
            static let captionStyle = Typography.IOS.footnote
            static let amountStyle = Typography.Amount.iOSTitle
            static let headerAlignment = HorizontalAlignment.center
            static let headerFrameAlignment = Alignment.center
        #endif
    }
#endif
