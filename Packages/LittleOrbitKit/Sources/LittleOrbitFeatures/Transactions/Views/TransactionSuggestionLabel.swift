#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// A payee or description suggestion under its field in the entry sheet: the text, and “Used 15 times”.
    struct TransactionSuggestionLabel: View {
        let suggestion: TransactionSuggestion

        var body: some View {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                    .accessibilityHidden(true)
                Text(suggestion.text)
                    .foregroundStyle(Color(ThemeColor.labelPrimary))
                Spacer()
                Text(TransactionFormViewModel.usageText(suggestion))
                    .font(.theme(Self.footnoteStyle))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Uses this suggestion")
        }

        #if os(macOS)
            private static let footnoteStyle = Typography.MacOS.footnote
        #else
            private static let footnoteStyle = Typography.IOS.footnote
        #endif
    }
#endif
