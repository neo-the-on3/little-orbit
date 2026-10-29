#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The import sheet: Columns, the target account when the file names none, Match, Review and the summary.
    /// Standard grouped forms, lists and controls; all logic is in `CSVImportViewModel`.
    struct CSVImportSheet: View {
        @Bindable var model: CSVImportViewModel
        /// For the shared store-change signal (D327.1).
        let feature: ImportExportFeature
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                stepContainer
                    .navigationTitle(ImportExportText.importTitle)
                    .navigationSubtitle(model.stepTitle)
                    .toolbar { toolbar }
                    .overlay {
                        if model.isWorking {
                            ProgressView(model.workingText)
                                .padding()
                                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        }
                    }
            }
            #if os(macOS)
                // Small enough for a default-size window; the form scrolls when the steps run longer.
                .frame(
                    minWidth: 520,
                    idealWidth: 600,
                    maxWidth: .infinity,
                    minHeight: 320,
                    idealHeight: 420,
                    maxHeight: .infinity,
                )
            #endif
            // Nothing is saved before Import, but the user's column and match choices would be lost.
            .interactiveDismissDisabled(model.step != .summary)
            // A tapped reminder closes the sheet first only when nothing would be lost (S33).
            .openSheet(hasUnsavedEdits: { model.hasUnsavedEdits }, close: { dismiss() })
            .alert(
                model.alert?.title ?? "",
                isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                presenting: model.alert,
            ) { _ in
                Button(ImportExportText.okay) {}
            } message: { alert in
                Text(alert.message)
            }
            // D281: a confirmation dialog on iOS; SwiftUI shows the same dialog as an alert on the Mac.
            .confirmationDialog(model.undoTitle, isPresented: $model.isConfirmingUndo, titleVisibility: .visible) {
                Button(ImportExportText.remove, role: .destructive) { model.undo() }
                Button(ImportExportText.cancel, role: .cancel) {}
            } message: {
                Text(model.undoMessage)
            }
            .onAppear { model.announce = { AccessibilityNotification.Announcement($0).post() } }
            .onChange(of: feature.ledgerRevision) {
                Task { await model.dataChanged() }
            }
            .onDisappear { model.close() }
        }

        /// Match and Review list a row per name or per file row, so they're a `List`, which lays out only the
        /// rows on screen, with or without VoiceOver or another accessibility client. A grouped `Form` lays out
        /// every row on the Mac, which hung a 5,200-row file (Tester's Mac pass on #190). The short steps stay a
        /// grouped `Form`.
        @ViewBuilder
        private var stepContainer: some View {
            switch model.step {
            case .match, .review:
                List { stepContent }
            case .pickFile, .columns, .account, .summary:
                Form { stepContent }
                    .formStyle(.grouped)
            }
        }

        @ViewBuilder
        private var stepContent: some View {
            // D327.1: one line of secondary footnote text, the first thing under the step's name. Text only, not
            // an alert or a banner; VoiceOver hears it once, through `model.announce`.
            if let notice = model.dataChangedNotice {
                Section {
                } footer: {
                    Text(notice)
                }
            }
            switch model.step {
            case .pickFile, .columns: CSVColumnsStep(model: model)
            case .account: CSVImportAccountPickerSection(model: model)
            case .match: CSVMatchStep(model: model)
            case .review: CSVReviewStep(model: model)
            case .summary: CSVSummaryStep(model: model)
            }
        }

        #if os(iOS)
            /// iOS Cancel in `.topBarLeading`, after Back: it keeps the cancel role and Escape that
            /// `.cancellationAction` gave it. Off while “Importing…” shows, so the sheet can't close mid-save (NB2
            /// on #190).
            private var cancelButton: some View {
                Button(ImportExportText.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
            }
        #endif

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if model.step == .summary {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ImportExportText.done) { dismiss() }
                }
            } else {
                #if os(iOS)
                    // Leading, in this order: ‹ Back, then Cancel (UI Designer, 26 Oct). Back is a plain button with
                    // the system chevron, since the steps swap in one view rather than being pushed (a
                    // NavigationStack push is #217). Both are .topBarLeading so the order is the declaration order;
                    // Cancel keeps its cancel role and Escape. They fit beside the title and Next or Import on a
                    // 375 pt iPhone SE or mini.
                    if model.canGoBack {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                model.back()
                            } label: {
                                Label(ImportExportText.back, systemImage: "chevron.left")
                                    .labelStyle(.titleAndIcon)
                            }
                            .disabled(model.isWorking)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        cancelButton
                    }
                #else
                    ToolbarItem(placement: .cancellationAction) {
                        // Off while “Importing…” shows, so the sheet can't close mid-save (NB2 on #190).
                        Button(ImportExportText.cancel) { dismiss() }
                            .disabled(model.isWorking)
                    }
                    if model.canGoBack {
                        ToolbarItem(placement: .navigation) {
                            Button(ImportExportText.back) { model.back() }
                                .disabled(model.isWorking)
                        }
                    }
                #endif
                // Review's one Import is here, so it's reachable however long the page is and Return imports on
                // the Mac: “Import” on iOS, “Import N Transactions” as the Mac sheet's default (UI Designer, 26 Oct).
                ToolbarItem(placement: .confirmationAction) {
                    if model.step == .review {
                        Button(model.importActionTitle(on: .current)) { Task { await model.commit() } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!model.canImport)
                    } else {
                        Button(ImportExportText.next) { Task { await model.next() } }
                            .disabled(!model.canGoNext || model.isWorking)
                    }
                }
            }
        }
    }
#endif
