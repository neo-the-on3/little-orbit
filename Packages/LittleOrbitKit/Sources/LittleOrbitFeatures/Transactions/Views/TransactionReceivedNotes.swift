#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// The footnotes under a transfer's Received field (D17): the read-only rate once both amounts read.
    struct TransactionReceivedNotes: View {
        let rate: String?

        var body: some View {
            if let rate {
                Label {
                    Text(rate)
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                        .accessibilityHidden(true)
                }
                .font(.theme(Self.footnoteStyle))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
            }
        }

        #if os(macOS)
            private static let footnoteStyle = Typography.MacOS.footnote
        #else
            private static let footnoteStyle = Typography.IOS.footnote
        #endif
    }
#endif
