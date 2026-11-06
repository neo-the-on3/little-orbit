#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// One focus stop, with a whole phrase. Stack the visual label and number when large text needs it.
    struct ImportReviewCountView: View {
        let row: ImportReviewCount

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(row.title)
                        .fixedSize()
                    Spacer()
                    Text(row.count.formatted())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                VStack(alignment: .leading) {
                    Text(row.title)
                    Text(row.count.formatted())
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.spoken)
        }
    }
#endif
