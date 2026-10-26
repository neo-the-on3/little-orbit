#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// A history row (Figma 25:501): icon, title, subtitle and Upcoming tag, then the amount and the balance
    /// after it. At accessibility sizes it stacks and nothing truncates (Figma 30:3861).
    struct TransactionRowView: View {
        let row: TransactionRowModel
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stacked
                } else {
                    // The inline row only when its one-line subtitle fits; otherwise the stacked layout, so the
                    // date is never cut off (UI Designer's D170 U1, as account rows do, D168).
                    ViewThatFits(in: .horizontal) {
                        inline
                        stacked
                    }
                }
            }
            .frame(minHeight: Layout.minimumTargetIOS)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        }

        private var inline: some View {
            HStack(spacing: Spacing.space3) {
                icon
                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                    title.lineLimit(1)
                    subtitle.lineLimit(1)
                    if row.isUpcoming {
                        tags
                    }
                }
                Spacer(minLength: Spacing.space2)
                VStack(alignment: .trailing, spacing: Spacing.spaceHalf) {
                    amount
                    balance
                }
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            }
        }

        /// At accessibility sizes the icon sits beside the title and everything below uses the full row width,
        /// so words wrap whole instead of breaking (UI Designer, #87 UI2).
        private var stacked: some View {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                HStack(alignment: .center, spacing: Spacing.space3) {
                    icon
                    title
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                subtitle
                    .fixedSize(horizontal: false, vertical: true)
                if row.isUpcoming {
                    tags
                }
                amount
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                balance
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// "Upcoming", and "Scheduled" beside it on a scheduled occurrence; a future row the user entered has no
        /// Scheduled tag (S85).
        private var tags: some View {
            HStack(spacing: Spacing.space1) {
                UpcomingTag()
                if row.isScheduled {
                    ScheduledTag()
                }
            }
        }

        private var icon: some View {
            AccountIconView(symbolName: row.symbolName)
        }

        private var title: some View {
            Text(row.title)
                .font(.theme(Typography.IOS.body))
                .foregroundStyle(Color(ThemeColor.labelPrimary))
        }

        private var subtitle: some View {
            Text(row.subtitle)
                .font(.theme(Typography.IOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }

        private var amount: some View {
            Text(row.compactAmountText)
                .font(.theme(Typography.Amount.iOSBody))
                .foregroundStyle(row.amountTone.color)
        }

        private var balance: some View {
            Text(row.balanceText)
                .font(.theme(Typography.IOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }
    }

    /// The "Upcoming" tag on future-dated rows (D21).
    struct UpcomingTag: View {
        var body: some View {
            HistoryTag(label: Text("Upcoming"), symbol: "clock")
        }
    }

    /// The "Scheduled" tag beside "Upcoming" on a scheduled occurrence that isn't recorded yet (S85). It's drawn
    /// exactly as the Upcoming tag, with its own word and symbol (UI Designer, #203 item 1).
    struct ScheduledTag: View {
        var body: some View {
            HistoryTag(label: Text(HistoryScheduledText.tag), symbol: "calendar.badge.clock")
        }
    }

    /// One tag on a history row: a symbol and a word in the info colours, in a capsule. An image and text, not a
    /// `Label`: in the history row a `Label` drew only its clock (Tester's #87 recheck, bug 7), and no label style
    /// can drop the word here.
    struct HistoryTag: View {
        let label: Text
        let symbol: String

        var body: some View {
            HStack(spacing: Spacing.space1) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                label
            }
            .accessibilityElement(children: .combine)
            .font(.theme(Typography.IOS.caption1))
            // One word on one line: never split as "Upcom-ing" (UI Designer, #87 UI2).
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color(ThemeColor.statusInfo))
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, Spacing.spaceHalf)
            .background(Color(ThemeColor.statusInfoBg), in: Capsule())
        }
    }

    /// A capsule, or at accessibility sizes a rounded rectangle, so wrapped lines don't crowd the round ends
    /// (Tester's #87 recheck).
    enum ToastShape {
        static func shape(_ size: DynamicTypeSize) -> RoundedRectangle {
            RoundedRectangle(cornerRadius: size.isAccessibilitySize ? Radius.large : Radius.full, style: .continuous)
        }
    }

    /// The iOS and iPadOS delete toast, with Undo (D164.2; Figma 25:899 light, 30:2744 dark). It sits above
    /// the bottom safe area and never takes focus. It closes itself after about 8 seconds, pausing while it is
    /// touched; with VoiceOver on it is announced and stays until dismissed or the next action.
    struct UndoToastView: View {
        let toast: UndoToast
        let onUndo: () -> Void
        let onTimeout: () -> Void
        @State private var isTouched = false
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(spacing: Spacing.space4) {
                message
                    .foregroundStyle(Color(ThemeColor.labelPrimary))
                    // One VoiceOver element with the whole message in either layout, even when the figure has
                    // its own line; Undo is the toast's button (D164, D172 V1). Grouping inside the
                    // `ViewThatFits` still exposed the stacked lines separately.
                    .accessibilityRepresentation { Text(toast.message) }
                Button("Undo", action: onUndo)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(ThemeColor.accentDefault))
            }
            .font(.theme(Typography.IOS.subheadline))
            .padding(.horizontal, Spacing.space5)
            .padding(.vertical, Spacing.space2)
            .frame(minHeight: Layout.minimumTargetIOS)
            // A system material, so it reads over any row in light and dark (D164.2).
            .background(.regularMaterial, in: ToastShape.shape(dynamicTypeSize))
            // The design system's floating shadow: light mode only (docs/design-tokens.md).
            .themeElevation(Elevation.popover)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isTouched = true }
                    .onEnded { _ in isTouched = false }
            )
            .accessibilityElement(children: .contain)
            // Under VoiceOver it stays until dismissed (D164.2): the two-finger scrub, or the Dismiss action.
            .accessibilityAction(.escape, onTimeout)
            .accessibilityAction(named: "Dismiss", onTimeout)
            .task(id: toast.stepID) { await runTimer() }
        }

        /// The message on one line when it fits. Otherwise a signed amount such as "+₹250.00" keeps its own line,
        /// breaking around it, never inside, and scales down only if it alone is too wide (D169, D170 U2).
        @ViewBuilder
        private var message: some View {
            if let parts = toast.figureParts {
                ViewThatFits(in: .horizontal) {
                    Text(toast.message)
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: 0) {
                        if !parts.before.isEmpty {
                            Text(parts.before)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(parts.figure)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !parts.after.isEmpty {
                            Text(parts.after)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Text(toast.message)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func runTimer() async {
            AccessibilityNotification.Announcement(toast.message).post()
            guard !voiceOverEnabled else {
                return
            }
            var left = 8.0
            while left > 0 {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled {
                    return
                }
                if !isTouched {
                    left -= 0.1
                }
            }
            onTimeout()
        }
    }

    /// "Restored 5 transactions in Household Card", with Show, after an Undo or Redo of a change that isn't on
    /// screen (D164.3). Show is the only way it navigates. On iOS and iPadOS it floats above the bottom safe
    /// area; on macOS it's a small banner under the toolbar.
    struct UndoNoticeView: View {
        let notice: UndoNotice
        let onShow: (UUID) -> Void
        let onDismiss: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            banner
                // Under VoiceOver it stays until dismissed (D165.3): the two-finger scrub, or Dismiss.
                .accessibilityAction(.escape, onDismiss)
                .accessibilityAction(named: "Dismiss", onDismiss)
        }

        @ViewBuilder
        private var banner: some View {
            #if os(macOS)
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.space3) {
                        content
                        Spacer(minLength: 0)
                    }
                    .font(.theme(Typography.MacOS.callout))
                    .padding(.horizontal, Spacing.space4)
                    .padding(.vertical, Spacing.space2)
                    Divider()
                }
                .background(.bar)
                .accessibilityElement(children: .contain)
            #else
                HStack(spacing: Spacing.space4) { content }
                    .font(.theme(Typography.IOS.subheadline))
                    .padding(.horizontal, Spacing.space5)
                    .padding(.vertical, Spacing.space2)
                    .frame(minHeight: Layout.minimumTargetIOS)
                    .background(.regularMaterial, in: ToastShape.shape(dynamicTypeSize))
                    .themeElevation(Elevation.popover)
                    .padding(.bottom, Spacing.space2)
                    .accessibilityElement(children: .contain)
            #endif
        }

        @ViewBuilder
        private var content: some View {
            Text(notice.message)
                .foregroundStyle(Color(ThemeColor.labelPrimary))
                .fixedSize(horizontal: false, vertical: true)
            if let accountID = notice.accountID {
                Button("Show") { onShow(accountID) }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(ThemeColor.accentDefault))
            }
        }
    }
#endif
