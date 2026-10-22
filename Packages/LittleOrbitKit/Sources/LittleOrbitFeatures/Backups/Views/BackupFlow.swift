#if canImport(SwiftUI)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI
    import UniformTypeIdentifiers

    extension UTType {
        /// `.littleorbit-backup`, which the iOS and macOS apps declare as an exported type conforming to
        /// `public.data` (D195a.1, L19). They don't declare a document type, so opening the file from Files or Finder
        /// doesn't start a restore in #40 (D197.3, L39).
        public static var littleOrbitBackup: UTType {
            UTType(exportedAs: BackupFormat.typeIdentifier, conformingTo: .data)
        }
    }

    /// An exported backup's file, for the system save panel or Files. It's handed over by URL and never read into
    /// memory (B2). It's never opened: the apps declare no document types (D197.3).
    struct BackupFileDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.littleOrbitBackup] }

        let url: URL

        init(url: URL) {
            self.url = url
        }

        init(configuration: ReadConfiguration) throws {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            // Without `.immediate`, the wrapper refers to the file instead of reading it in.
            try FileWrapper(url: url, options: [])
        }
    }

    /// The alerts, sheets, file panels and restore progress of the iOS and macOS Backups screens.
    ///
    /// Everything it presents is this window's own (`BackupsWindow`), so a prompt never shows in another window
    /// (Tech Architect). It goes on the screen that triggers them: the list or tab, and on iOS also the pushed
    /// backup detail, so the warning shows over the detail (Tester B3). Only the screen on top is `isActive`, so
    /// nothing is presented twice. The restore warning and the delete dialog hand their presented item to the
    /// action, since SwiftUI clears the binding before the action runs (Tester B1, B2).
    struct BackupFlowModifier: ViewModifier {
        @Bindable var window: BackupsWindow
        @Binding var isPickingFile: Bool
        var isActive = true

        private var model: BackupsViewModel {
            window.model
        }

        /// `window[keyPath]` as a presentation binding that's empty while this screen isn't on top.
        private func presented<Item>(_ keyPath: ReferenceWritableKeyPath<BackupsWindow, Item?>) -> Binding<Item?> {
            Binding(
                get: { isActive ? window[keyPath: keyPath] : nil },
                set: { if isActive { window[keyPath: keyPath] = $0 } },
            )
        }

        private func isPresented<Item>(_ keyPath: ReferenceWritableKeyPath<BackupsWindow, Item?>) -> Binding<Bool> {
            Binding(
                get: { isActive && window[keyPath: keyPath] != nil },
                set: { if !$0 && isActive { window[keyPath: keyPath] = nil } },
            )
        }

        func body(content: Content) -> some View {
            content
                .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.littleOrbitBackup, .data]) { result in
                    guard case .success(let url) = result else {
                        return
                    }
                    // Read where it is, off the main thread, in chunks: never loaded whole (B1.1). The reader holds the
                    // file's security scope for each pass.
                    Task { await window.restoreFromFile(.file(url)) }
                }
                .fileExporter(
                    isPresented: isPresented(\.pendingExport),
                    document: window.pendingExport.map { BackupFileDocument(url: $0.url) },
                    contentType: .littleOrbitBackup,
                    defaultFilename: window.pendingExport.map {
                        String($0.fileName.dropLast(BackupFormat.fileExtension.count + 1))
                    },
                ) { _ in
                    window.finishExport()
                }
                .sheet(item: presented(\.exportPrompt)) { prompt in
                    ExportBackupSheet(window: window, prompt: prompt)
                }
                .alert(
                    BackupPresentation.restoreTitle,
                    isPresented: isPresented(\.restorePrompt),
                    presenting: window.restorePrompt,
                ) { prompt in
                    Button("Restore", role: .destructive) {
                        Task { await window.confirmRestore(prompt) }
                    }
                    Button("Cancel", role: .cancel) {
                        window.cancelRestore()
                    }
                    // Return cancels, never restores (UI Designer); Escape already cancels.
                    .keyboardShortcut(.defaultAction)
                } message: { prompt in
                    Text(prompt.message)
                }
                .confirmationDialog(
                    BackupPresentation.deleteTitle,
                    isPresented: isPresented(\.deletePrompt),
                    titleVisibility: .visible,
                    presenting: window.deletePrompt,
                ) { row in
                    Button(BackupPresentation.deleteBackup, role: .destructive) {
                        Task { await window.confirmDelete(row) }
                    }
                    Button("Cancel", role: .cancel) { window.cancelDelete() }
                } message: { _ in
                    Text(model.presentation.deleteMessage)
                }
                .alert(
                    window.alert?.title ?? "",
                    isPresented: isPresented(\.alert),
                    presenting: window.alert,
                ) { _ in
                    Button("OK") { window.dismissAlert() }
                } message: { alert in
                    Text(alert.message)
                }
                .alert(
                    "Something Went Wrong",
                    isPresented: isPresented(\.errorMessage),
                ) {
                    Button("OK") { window.dismissError() }
                } message: {
                    Text(window.errorMessage ?? "")
                }
                // Only the window that started the restore shows its progress; the others have their actions off.
                .sheet(
                    isPresented: Binding(get: { isActive && window.isShowingRestoreProgress }, set: { _ in })
                ) {
                    RestoringBackupView(window: window)
                        .interactiveDismissDisabled()
                }
                #if os(iOS)
                    // The iOS toast; macOS shows `restoredMessage` inline in the tab (frame 169:5253).
                    .overlay(alignment: .bottom) {
                        if isActive, let toast = window.toast {
                            Text(toast)
                            .font(.subheadline)
                            .padding(.horizontal, Spacing.space4)
                            .padding(.vertical, Spacing.space3)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, Spacing.space6)
                            .accessibilityAddTraits(.isStaticText)
                            .task {
                                try? await Task.sleep(for: .seconds(4))
                                window.dismissToast()
                            }
                        }
                    }
                #endif
        }
    }

    /// Export Backup, in order: the backup's summary in secondary text, the note that the file isn't encrypted,
    /// then Cancel and Export, which goes straight to the share sheet or save panel. No password and no extra
    /// confirmation (R1, S64, D182.4, D186).
    /// - iOS (frame 277:4915): the Backup cell with the date, and the summary and the note in that section's footer.
    ///   "Cancel" and "Export" sit in the navigation bar.
    /// - macOS (frame 277:4581): a sheet shows no navigation title, so "Export Backup" is an in-content heading.
    ///   The summary and the note follow, with Cancel and "Export…" at the bottom right.
    /// The note is a Label with a warning triangle in the Theme's `status/warning` colour on both platforms.
    struct ExportBackupSheet: View {
        let window: BackupsWindow
        let prompt: BackupExportPrompt
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    #if os(macOS)
                        Section {
                            Text(BackupPresentation.exportTitle)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text(prompt.summary)
                                .foregroundStyle(.secondary)
                            warning
                        }
                    #else
                        Section {
                            LabeledContent("Backup", value: prompt.dateText)
                        } footer: {
                            VStack(alignment: .leading) {
                                Text(prompt.summary)
                                warning
                            }
                        }
                    #endif
                }
                .formStyle(.grouped)
                .navigationTitle(BackupPresentation.exportTitle)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            window.cancelExport()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Self.confirmTitle) {
                            Task { await window.export(prompt) }
                        }
                    }
                }
            }
            #if os(macOS)
                .frame(minWidth: 460, minHeight: 240)
            #endif
        }

        /// "This file isn't encrypted…" with the warning triangle, in the warning colour. VoiceOver reads it as one
        /// element with an explicit label, "Warning, This file isn't encrypted…", so the icon isn't a separate stop
        /// and the order doesn't depend on the symbol's own label.
        private var warning: some View {
            Label(BackupPresentation.unencryptedWarning, systemImage: BackupPresentation.unencryptedWarningSymbol)
                .foregroundStyle(Color(ThemeColor.statusWarning))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BackupPresentation.unencryptedWarningAccessibilityLabel)
        }

        private static var confirmTitle: String {
            #if os(iOS)
                BackupPresentation.exportConfirm
            #else
                BackupPresentation.exportEllipsis
            #endif
        }
    }

    /// The restore progress screen. It has no Cancel and can't be dismissed (D116.2, S54).
    struct RestoringBackupView: View {
        let window: BackupsWindow

        private var model: BackupsViewModel {
            window.model
        }

        var body: some View {
            VStack(spacing: Spacing.space4) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(BackupPresentation.restoringTitle)
                    .font(.title2)
                if let summary = window.restoringSummary {
                    Text(summary).foregroundStyle(.secondary)
                }
                // The steps sit under the bar as its current-value label (Figma 165:1028, UI Designer), and
                // VoiceOver reads the step, not just a percentage.
                ProgressView(value: model.restoreFraction) {
                    EmptyView()
                } currentValueLabel: {
                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        Label(
                            BackupPresentation.savedCurrentDataStep,
                            systemImage: model.isCurrentDataSaved ? "checkmark.circle.fill" : "circle",
                        )
                        if model.isCurrentDataSaved {
                            Label(BackupPresentation.replacingDataStep, systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .font(.subheadline)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BackupPresentation.restoringTitle)
                .accessibilityValue(model.restoreStepText)
                Text(BackupPresentation.restoreInterruptedNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.space8)
            #if os(macOS)
                .frame(minWidth: 420)
                .onExitCommand {}
            #endif
        }
    }
#endif

#if canImport(SwiftUI)
    /// The two Keep steppers (D195.4, L11): standard Stepper rows, as UI Designer approved. Off while a backup or
    /// restore runs (L14), and while this window's 'Delete N Backups?' waits. That prompt belongs to the
    /// window, not the shared view model, so the steppers show its proposed values only here (Tech Architect).
    struct BackupKeepSteppers: View {
        let window: BackupsWindow

        private var shown: BackupRetention {
            window.shownRetention
        }

        var body: some View {
            Stepper(
                value: Binding(
                    get: { shown.recentAutomatic },
                    set: { value in
                        propose(BackupRetention(recentAutomatic: value, monthlyMonths: shown.monthlyMonths))
                    },
                ),
                in: BackupRetention.recentAutomaticRange,
            ) {
                LabeledContent(BackupPresentation.recentAutomaticBackups, value: shown.recentAutomatic.formatted())
            }
            // VoiceOver announces the new value on each swipe up or down (UI Designer).
            .accessibilityValue(shown.recentAutomatic.formatted())
            .disabled(!window.retentionEnabled)
            Stepper(
                value: Binding(
                    get: { shown.monthlyMonths },
                    set: { value in
                        propose(BackupRetention(recentAutomatic: shown.recentAutomatic, monthlyMonths: value))
                    },
                ),
                in: BackupRetention.monthlyMonthsRange,
            ) {
                LabeledContent(
                    BackupPresentation.monthlyBackups,
                    value: window.model.presentation.monthlyValue(shown.monthlyMonths),
                )
            }
            .accessibilityValue(window.model.presentation.monthlyValue(shown.monthlyMonths))
            .disabled(!window.retentionEnabled)
        }

        private func propose(_ retention: BackupRetention) {
            Task { await window.proposeRetention(retention) }
        }
    }

    /// 'Delete 4 Backups?' after N or M was lowered in this window (L12, L13). Any dismissal that isn't Delete is
    /// Cancel: the prompt is dropped and the saved N and M show again.
    struct BackupPruneAlert: ViewModifier {
        let window: BackupsWindow

        func body(content: Content) -> some View {
            content
                .alert(
                    window.prunePrompt?.title ?? "",
                    isPresented: Binding(
                        get: { window.prunePrompt != nil },
                        // Esc or any other dismissal is Cancel (L13).
                        set: { shown in
                            if !shown {
                                window.cancelPrune()
                            }
                        },
                    ),
                    presenting: window.prunePrompt,
                ) { presented in
                    Button(presented.confirmTitle, role: .destructive) {
                        Task { await window.confirmPrune(presented) }
                    }
                    Button("Cancel", role: .cancel) {
                        window.cancelPrune()
                    }
                    // Delete is never the default button (L12).
                    .keyboardShortcut(.defaultAction)
                } message: { presented in
                    Text(presented.message)
                }
        }
    }
#endif
