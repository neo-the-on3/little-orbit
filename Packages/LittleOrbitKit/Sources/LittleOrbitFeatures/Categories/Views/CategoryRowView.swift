#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// A category's icon chip: its white symbol on its `category/*` hue (UI Designer's #24 handoff).
    struct CategoryChip: View {
        let symbolName: String
        let hue: CategoryHue
        var isSubcategory = false
        @ScaledMetric private var size: CGFloat = 32
        @ScaledMetric private var subcategorySize: CGFloat = 24

        var body: some View {
            let side = isSubcategory ? subcategorySize : size
            Image(systemName: symbolName)
                .font(isSubcategory ? .caption : .subheadline)
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(Color(hue.token), in: .circle)
                .accessibilityHidden(true)
        }
    }

    /// A row of the category tree: the chip, the name and "Expense · 25 transactions". VoiceOver reads only
    /// the name and the subtitle, as one element; the decorative icon is hidden (Tester and UI Designer).
    struct CategoryRowView: View {
        let row: CategoryRow

        var body: some View {
            HStack {
                CategoryChip(symbolName: row.symbolName, hue: row.hue, isSubcategory: row.isSubcategory)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(row.name)
                        .lineLimit(2)
                    Text(row.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityValue(row.subtitle)
        }
    }
#endif
