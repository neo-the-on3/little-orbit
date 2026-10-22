#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// An iOS account row (Figma 14:1424): icon, name, type or credit subtitle, balance.
    ///
    /// An amount, a name or a subtitle figure is never split or truncated (UI Designer on #82 B3/B4, B5, B6).
    /// - Inline: icon, name and subtitle, then the amount at its natural width. Used at standard sizes when the
    ///   name and subtitle each fit on one line next to the amount (B5).
    /// - Stacked: the icon sits inline with the name; the subtitle and the amount span the full label width.
    ///   Used at every accessibility size, and at standard sizes when the inline row doesn't fit the width the
    ///   List gives the label, for example at XXL/XXXL or with the Edit-mode reorder handle (#82 B8, B10).
    ///   The name and subtitle wrap at word boundaries instead of truncating; the subtitle's figure is never
    ///   split (D169). The amount is one line and scales (to 0.5) only at accessibility sizes (B6).
    /// The row stays the label of a standard NavigationLink with the system chevron, and is one VoiceOver element.
    struct AccountRowView: View {
        let row: AccountRowModel
        /// In a section such as Credit the type prefix is dropped from the subtitle (UI Designer, #82 U1).
        var inTypeSection = true
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stacked
                } else {
                    // ViewThatFits takes the inline row only when its one-line ideal width fits (#82 B8, B10).
                    ViewThatFits(in: .horizontal) {
                        inline
                        stacked
                    }
                }
            }
            .frame(minHeight: Layout.minimumTargetIOS)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        }

        private var inline: some View {
            HStack(spacing: Spacing.space3) {
                AccountIconView(symbolName: row.symbolName)
                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                    nameLine.lineLimit(1)
                    subtitle.lineLimit(1)
                }
                // The text column takes every point the amount doesn't need (B5): no Spacer competes for it.
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                balance
                    .lineLimit(1)
                    .fixedSize()
            }
        }

        private var stacked: some View {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                HStack(alignment: .top, spacing: Spacing.space3) {
                    AccountIconView(symbolName: row.symbolName)
                    nameLine
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                stackedSubtitle
                balance
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.5 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var nameLine: some View {
            HStack(spacing: Spacing.space1) {
                Text(row.name)
                    .font(.theme(Typography.IOS.body))
                    .foregroundStyle(Color(ThemeColor.labelPrimary))
                if row.isHidden {
                    StatusTag(text: "Hidden")
                }
                if row.isExcluded {
                    StatusTag(text: "Excluded")
                }
            }
        }

        private var subtitle: some View {
            let subtitle = row.subtitle(inTypeSection: inTypeSection)
            return subtitleText(subtitle.text, isWarning: subtitle.isWarning)
        }

        /// D169 (#82 B10): the figure never breaks mid-number. The line stays whole when it fits; otherwise it
        /// breaks before "available" or after "Over limit by", and the figure keeps its own line at the size of its
        /// words. It scales down, to 0.7 at most, only if it alone is wider than the label (Edit mode at AX-XXXL,
        /// D170 B11, #95). Text without a figure wraps.
        @ViewBuilder
        private var stackedSubtitle: some View {
            let subtitle = row.subtitle(inTypeSection: inTypeSection)
            if let parts = subtitle.figureParts {
                ViewThatFits(in: .horizontal) {
                    subtitleText(subtitle.text, isWarning: subtitle.isWarning)
                        .lineLimit(1)
                    stacked(parts, isWarning: subtitle.isWarning, minimumScale: 1)
                    stacked(parts, isWarning: subtitle.isWarning, minimumScale: 0.7)
                }
            } else {
                subtitleText(subtitle.text, isWarning: subtitle.isWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        /// The subtitle broken around its figure, which keeps its own line.
        private func stacked(
            _ parts: AccountSubtitle.FigureParts,
            isWarning: Bool,
            minimumScale: CGFloat,
        ) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                if !parts.before.isEmpty {
                    subtitleText(parts.before, isWarning: isWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                subtitleText(parts.figure, isWarning: isWarning)
                    .lineLimit(1)
                    .minimumScaleFactor(minimumScale)
                if !parts.after.isEmpty {
                    subtitleText(parts.after, isWarning: isWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        private func subtitleText(_ text: String, isWarning: Bool) -> some View {
            Text(text)
                .font(.theme(Typography.IOS.footnote))
                .foregroundStyle(Color(isWarning ? ThemeColor.statusOverspent : ThemeColor.labelSecondary))
        }

        private var balance: some View {
            Text(row.balanceText)
                .font(.theme(Typography.Amount.iOSBody))
                .foregroundStyle(row.balanceTone.color)
        }
    }

    /// A Budgets, Scheduled or Reports row on iOS, with its subtitle and count badge.
    struct HomeRowView: View {
        let row: HomeRowModel

        var body: some View {
            HStack(spacing: Spacing.space3) {
                HomeIconView(destination: row.destination)
                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                    Text(row.title)
                        .font(.theme(Typography.IOS.body))
                        .foregroundStyle(Color(ThemeColor.labelPrimary))
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.theme(Typography.IOS.footnote))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                    }
                }
                Spacer(minLength: Spacing.space2)
                if let badge = row.badge {
                    CountBadgeView(text: badge)
                }
            }
            .frame(minHeight: Layout.minimumTargetIOS)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        }
    }
#endif
