#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// The account header (macOS Figma 14:1846 detail pane), with the D114 empty state below it.
    /// The transaction list itself arrives with the transactions issue.
    struct AccountDetailView: View {
        let row: AccountRowModel
        let onEdit: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // #82 B9: when the header and empty state are taller than the screen (accessibility sizes), the
            // detail scrolls instead of compressing the header, which used to shrink the balance below its
            // caption. When everything fits, the empty state stays centred in the space under the header.
            ViewThatFits(in: .vertical) {
                content(fillsHeight: true)
                ScrollView {
                    content(fillsHeight: false)
                }
            }
            .navigationTitle(row.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", action: onEdit)
                }
            }
        }

        private func content(fillsHeight: Bool) -> some View {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                header
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil)
            }
            .padding(Self.margin)
        }

        private var header: some View {
            // Figma 145:17021: name, then the balance on its own line, then the subtitle. The
            // over-limit line shows once, in red, under the subtitle.
            VStack(alignment: .leading, spacing: Spacing.space1) {
                HStack(spacing: Spacing.space3) {
                    AccountIconView(symbolName: row.symbolName, size: 40)
                    Text(row.name)
                        .font(.theme(Self.titleStyle))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The balance keeps its full style on its own line, so it is never smaller than the
                // caption. It scales only when the number alone is wider than the screen: to 0.8 at
                // most, or 0.5 at accessibility sizes, so it never truncates (UI Designer, #82 U4).
                // Its height is fixed, so a short screen can't shrink it vertically (#82 B9).
                Text(row.balanceText)
                    .font(.theme(Self.amountStyle))
                    .foregroundStyle(row.balanceTone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.5 : 0.8)
                    .fixedSize(horizontal: false, vertical: true)
                // The caption and over-limit line wrap and never truncate (#82 B2, U4).
                Text(row.detailCaption)
                    .font(.theme(Self.captionStyle))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = row.warning {
                    Text(warning)
                        .font(.theme(Self.captionStyle))
                        .foregroundStyle(Color(ThemeColor.statusOverspent))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private var emptyState: some View {
            if row.hasTransactions {
                ContentUnavailableView(
                    "Transactions",
                    systemImage: "list.bullet",
                    description: Text("The transaction list for this account arrives with its own issue."),
                )
            } else {
                // D114: shown until the account has its first transaction, on either side
                // of a transfer. Scheduled items don't count.
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "tray",
                    description: Text("Transactions for this account will show here."),
                )
            }
        }

        #if os(macOS)
            private static let titleStyle = Typography.MacOS.title2
            private static let captionStyle = Typography.MacOS.footnote
            private static let amountStyle = Typography.Amount.macOSTitle
            private static let margin = Layout.marginMacOS
        #else
            private static let titleStyle = Typography.IOS.title2
            private static let captionStyle = Typography.IOS.footnote
            private static let amountStyle = Typography.Amount.iOSTitle
            private static let margin = Layout.marginIOS
        #endif
    }
#endif
