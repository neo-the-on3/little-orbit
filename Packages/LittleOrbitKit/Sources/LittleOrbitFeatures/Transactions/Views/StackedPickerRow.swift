#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// A picker row in the entry sheet. At accessibility sizes the label goes above the value and the value wraps
    /// onto more lines, never truncated in the middle; the row opens the same choices as a menu. VoiceOver reads
    /// the label once with the choice as the value, "Account, Everyday Savings" (Tester's #87 B2, B3). At other
    /// sizes the standard picker reads that way itself. `spoken`, when set, is what VoiceOver reads instead of
    /// `value`, such as "Groceries, under Food".
    struct StackedPickerRow<Content: View>: View {
        let title: String
        let value: String
        let spoken: String?
        let control: () -> Content
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        init(
            _ title: String,
            value: String,
            spoken: String? = nil,
            @ViewBuilder control: @escaping () -> Content,
        ) {
            self.title = title
            self.value = value
            self.spoken = spoken
            self.control = control
        }

        var body: some View {
            #if os(iOS)
                if dynamicTypeSize.isAccessibilitySize {
                    Menu {
                        control()
                            .pickerStyle(.inline)
                            .labelsHidden()
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                            Text(title)
                                .foregroundStyle(Color(ThemeColor.labelPrimary))
                            Text(value)
                                .foregroundStyle(Color(ThemeColor.labelSecondary))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(spoken ?? value)
                    .accessibilityAddTraits(.isButton)
                } else {
                    control()
                }
            #else
                control()
            #endif
        }
    }
#endif
