#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitCore
    import LittleOrbitTheme
    import SwiftUI

    /// The progress of a Bulk Edit, its Undo or its Redo (#285, D398.3): the title, then a determinate bar
    /// labelled “Updating 3,334 transactions.” and, for the write, “Saving…” with the bar full, or moving when the
    /// save runs off the main actor (#285, B). It has no Cancel.
    struct BatchProgressView: View {
        let progress: BatchProgress

        private var message: some View {
            Text(progress.message)
                .font(.theme(Typography.MacOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                Text(progress.title)
                    .font(.theme(Typography.MacOS.headline))
                    .accessibilityAddTraits(.isHeader)
                if progress.showsIndeterminateBar {
                    // The save runs off the main actor (#285, B), so the bar moves while it runs. It switches once, and
                    // VoiceOver still reads the same "Saving…" label.
                    ProgressView {
                        message
                    }
                    .progressViewStyle(.linear)
                } else {
                    ProgressView(value: progress.value, total: Double(max(progress.total, 1))) {
                        message
                    }
                    .progressViewStyle(.linear)
                }
            }
            .padding(Layout.marginMacOS)
            .frame(minWidth: 460, alignment: .leading)
            .onAppear {
                BatchTrace.event("batch.sheet.firstFrame")
                // A save waiting for the sheet starts once it has drawn (D401).
                progress.sheetAppeared()
            }
            // A held announcement's fallback waits while the sheet is still drawn.
            .onDisappear { progress.sheetDisappeared() }
        }
    }

    extension View {
        /// The progress sheet for this window's Bulk Edit Undo or Redo, once it has run for half a second, or just
        /// before a long save (`BatchSheetPolicy`). It can't be dismissed; it goes when the work ends. Closing the
        /// window stops work that hasn't written yet.
        func batchProgressSheet(_ history: WindowUndoHistory) -> some View {
            sheet(
                isPresented: Binding(get: { history.batchProgress?.isShown ?? false }, set: { _ in }),
                // VoiceOver hears "Undid …" or "Redid …" once the sheet has gone (Tester2 on c8c6594).
                onDismiss: { history.batchSheetDismissed() },
            ) {
                // The ended batch's progress stays drawn while the sheet closes.
                if let progress = history.batchProgress ?? history.closingProgress {
                    BatchProgressView(progress: progress)
                        .interactiveDismissDisabled()
                }
            }
            .onDisappear { history.cancelBatch() }
        }
    }
#endif
