#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import Foundation
    import SwiftUI

    /// The category picker's items: a section per parent category, headed by the parent's name, with the
    /// parent first and its subcategories under it. Each item is a standard `Label` with its icon, so the
    /// items line up, and the hierarchy shows with the system's own grouping, not an indent (UI Designer,
    /// #87). VoiceOver reads the section header as the menu's group title, so a subcategory is heard under
    /// its parent. Goes inside a `Picker` whose selection is `UUID?`, with a text-only `currentValueLabel`
    /// and the model's `categorySpokenValue`, so the closed picker reads "Category, Groceries".
    struct CategoryPickerSections: View {
        let groups: [TransactionCategoryGroup]

        var body: some View {
            ForEach(groups) { group in
                if group.subcategories.isEmpty {
                    Section { item(group.parent) }
                } else {
                    Section(group.parent.name) {
                        item(group.parent)
                        ForEach(group.subcategories) { item($0) }
                    }
                }
            }
        }

        private func item(_ option: TransactionCategoryOption) -> some View {
            Label(option.name, systemImage: option.symbolName).tag(Optional(option.id))
        }
    }
#endif
