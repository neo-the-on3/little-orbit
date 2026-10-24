#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitTheme
    import SwiftUI

    /// The entry sheet's Category row on iOS (#24 16:7540): a button that opens the searchable picker with
    /// inline create. VoiceOver reads “Category” with the choice, “Groceries, under Food & Dining”, as the menu
    /// did. At accessibility sizes the value goes under the label and wraps. The picker reads the categories
    /// once, when the row is tapped, never while the form is drawn.
    struct TransactionCategoryButton: View {
        let model: TransactionFormViewModel
        @Binding var picker: CategoryPickerViewModel?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Button {
                picker = model.makeCategoryPicker()
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                            Text("Category")
                                .foregroundStyle(Color(ThemeColor.labelPrimary))
                            Text(model.categoryName)
                                .foregroundStyle(Color(ThemeColor.labelSecondary))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LabeledContent {
                            Text(model.categoryName)
                        } label: {
                            Text("Category")
                                .foregroundStyle(Color(ThemeColor.labelPrimary))
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Category")
            .accessibilityValue(model.categorySpokenValue)
            .accessibilityAddTraits(.isButton)
        }
    }
#endif
