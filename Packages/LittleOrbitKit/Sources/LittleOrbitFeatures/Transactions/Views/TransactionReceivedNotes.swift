#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// The footnotes under a transfer's Received field (D17): the plain “Enter the amount received in EUR.” hint
    /// while Save waits for it (#215, as #207's scheduled form), then the read-only rate once both amounts read.
    struct TransactionReceivedNotes: View {
        let hint: String?
        let rate: String?

        var body: some View {
            if let hint {
                // A hint, not an error. VoiceOver reads it as the field's accessibility hint, so it isn't read twice.
                Text(verbatim: hint)
                    .font(.theme(Self.footnoteStyle))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                    .accessibilityHidden(true)
            }
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
