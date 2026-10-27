#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitTheme
    import SwiftUI

    /// The progress of a Bulk Edit, its Undo or its Redo (#285, D398.3): the title, then a determinate bar
    /// labelled “Updating 3,334 transactions.” and, for the write, “Saving…” with the bar full. It has no Cancel.
    struct BatchProgressView: View {
        let progress: BatchProgress

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                Text(progress.title)
                    .font(.theme(Typography.MacOS.headline))
                    .accessibilityAddTraits(.isHeader)
                ProgressView(value: progress.value, total: Double(max(progress.total, 1))) {
                    Text(progress.message)
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                }
                .progressViewStyle(.linear)
            }
            .padding(Layout.marginMacOS)
            .frame(minWidth: 460, alignment: .leading)
        }
    }

    extension View {
        /// The progress sheet for this window's Bulk Edit Undo or Redo, once it has run for half a second. It
        /// can't be dismissed; it goes when the work ends. Closing the window stops work that hasn't written yet.
        func batchProgressSheet(_ history: WindowUndoHistory) -> some View {
            sheet(
                isPresented: Binding(get: { history.batchProgress?.isShown ?? false }, set: { _ in })
            ) {
                if let progress = history.batchProgress {
                    BatchProgressView(progress: progress)
                        .interactiveDismissDisabled()
                }
            }
            .onDisappear { history.cancelBatch() }
        }
    }
#endif
