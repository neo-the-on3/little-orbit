#if canImport(SwiftUI)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI
    import UniformTypeIdentifiers

    extension UTType {
        /// `.littleorbit-backup`. Declaring it in Info.plist, so the apps open these files from Files and
        /// Finder, comes with the document-type follow-up (#40 PR notes).
        public static var littleOrbitBackup: UTType {
            UTType(filenameExtension: BackupFormat.fileExtension, conformingTo: .data) ?? .data
        }
    }

    /// The bytes of an exported backup, for the system save panel or Files.
    struct BackupFileDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.littleOrbitBackup] }

        var data: Data

        init(data: Data) {
            self.data = data
        }

        init(configuration: ReadConfiguration) throws {
            data = configuration.file.regularFileContents ?? Data()
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }

    /// The alerts, sheets, file panels and restore progress shared by the iOS and macOS Backups screens.
    struct BackupFlowModifier: ViewModifier {
        @Bindable var model: BackupsViewModel
        @Binding var isPickingFile: Bool

        func body(content: Content) -> some View {
            content
                .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.littleOrbitBackup, .data]) { result in
                    guard case .success(let url) = result else {
                        return
                    }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if scoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = (try? Data(contentsOf: url)) ?? Data()
                    let name = url.lastPathComponent
                    Task { await model.restoreFromFile(data, fileName: name) }
                }
                .fileExporter(
                    isPresented: Binding(
                        get: { model.pendingExport != nil },
                        set: { if !$0 { model.pendingExport = nil } },
                    ),
                    document: model.pendingExport.map { BackupFileDocument(data: $0.data) },
                    contentType: .littleOrbitBackup,
                    defaultFilename: model.pendingExport.map {
                        String($0.fileName.dropLast(BackupFormat.fileExtension.count + 1))
                    },
                ) { _ in
                    model.pendingExport = nil
                }
                .sheet(item: $model.exportForm) { form in
                    ExportBackupSheet(model: model, form: form)
                }
                .sheet(item: $model.passwordPrompt) { prompt in
                    BackupPasswordSheet(model: model, prompt: prompt)
                }
                .alert(
                    BackupPresentation.restoreTitle,
                    isPresented: Binding(
                        get: { model.restorePrompt != nil },
                        set: { if !$0 { model.cancelRestore() } },
                    ),
                    presenting: model.restorePrompt,
                ) { _ in
                    Button("Restore", role: .destructive) {
                        Task { await model.confirmRestore() }
                    }
                    Button("Cancel", role: .cancel) {
                        model.cancelRestore()
                    }
                    // Return cancels, never restores (UI Designer); Escape already cancels.
                    .keyboardShortcut(.defaultAction)
                } message: { prompt in
                    Text(prompt.message)
                }
                .alert(
                    model.alert?.title ?? "",
                    isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                    presenting: model.alert,
                ) { _ in
                    Button("OK") { model.alert = nil }
                } message: { alert in
                    Text(alert.message)
                }
                .alert(
                    "Something Went Wrong",
                    isPresented: Binding(
                        get: { model.errorMessage != nil },
                        set: { if !$0 { model.errorMessage = nil } },
                    ),
                ) {
                    Button("OK") { model.errorMessage = nil }
                } message: {
                    Text(model.errorMessage ?? "")
                }
                .sheet(
                    isPresented: Binding(get: { model.restoreStep != nil }, set: { _ in })
                ) {
                    RestoringBackupView(model: model)
                        .interactiveDismissDisabled()
                }
                #if os(iOS)
                    // The iOS toast; macOS shows `restoredMessage` inline in the tab (frame 169:5253).
                    .overlay(alignment: .bottom) {
                        if let toast = model.toast {
                            Text(toast)
                            .font(.subheadline)
                            .padding(.horizontal, Spacing.space4)
                            .padding(.vertical, Spacing.space3)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, Spacing.space6)
                            .accessibilityAddTraits(.isStaticText)
                            .task {
                                try? await Task.sleep(for: .seconds(4))
                                model.toast = nil
                            }
                        }
                    }
                #endif
        }
    }

    /// Export Backup: an optional password with Confirm, no hint (D63, D96.2).
    struct ExportBackupSheet: View {
        let model: BackupsViewModel
        @Bindable var form: ExportBackupForm
        @Environment(\.dismiss) private var dismiss
        @State private var isExporting = false

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        #if os(macOS)
                            Text(model.presentation.exportSummary(form.record, now: Date()))
                        #else
                            LabeledContent("Backup", value: model.row(form.record.id)?.title ?? "")
                        #endif
                    }
                    Section {
                        SecureField("Password", text: $form.password, prompt: Text("Required for encryption"))
                            .foregroundStyle(form.isPasswordInvalid ? Color(ThemeColor.statusOverspent) : Color.primary)
                        SecureField("Confirm", text: $form.confirmation, prompt: Text("Repeat password"))
                            .foregroundStyle(
                                form.isConfirmationInvalid ? Color(ThemeColor.statusOverspent) : Color.primary
                            )
                    } header: {
                        Text("Password (Optional)")
                    } footer: {
                        VStack(alignment: .leading, spacing: Spacing.space2) {
                            if let message = form.validationMessage {
                                Text(message).foregroundStyle(Color(ThemeColor.statusOverspent))
                            }
                            Text(model.presentation.exportPasswordFooter)
                            if form.showsUnencryptedWarning {
                                Label(BackupPresentation.unencryptedWarning, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(Color(ThemeColor.statusWarning))
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(BackupPresentation.exportTitle)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            model.exportForm = nil
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Export") {
                            isExporting = true
                            Task {
                                await model.export(form)
                                isExporting = false
                            }
                        }
                        .disabled(!form.canExport || isExporting)
                    }
                }
            }
            #if os(macOS)
                .frame(minWidth: 460, minHeight: 360)
            #endif
        }
    }

    /// Enter Password for an encrypted backup. Retries are unlimited (D118.4).
    struct BackupPasswordSheet: View {
        let model: BackupsViewModel
        let prompt: BackupPasswordPrompt
        @State private var password = ""

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        if !prompt.fileName.isEmpty {
                            LabeledContent("File", value: prompt.fileName)
                        }
                    } footer: {
                        Text(BackupPresentation.passwordProtectedFooter)
                    }
                    Section {
                        SecureField("Password", text: $password)
                            .onSubmit(submit)
                    } footer: {
                        VStack(alignment: .leading, spacing: Spacing.space2) {
                            if let error = prompt.errorMessage {
                                Text(error).foregroundStyle(Color(ThemeColor.statusOverspent))
                            }
                            Text(BackupPresentation.forgottenPasswordFooter)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(BackupPresentation.enterPasswordTitle)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancelPassword() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Restore", action: submit)
                    }
                }
            }
            #if os(macOS)
                .frame(minWidth: 420, minHeight: 260)
            #endif
        }

        private func submit() {
            let attempt = password
            password = ""
            Task { await model.submitPassword(attempt) }
        }
    }

    /// The restore progress screen. It has no Cancel and can't be dismissed (D116.2, S54).
    struct RestoringBackupView: View {
        let model: BackupsViewModel

        var body: some View {
            VStack(spacing: Spacing.space4) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(BackupPresentation.restoringTitle)
                    .font(.title2)
                if let summary = model.restoringSummary {
                    Text(summary).foregroundStyle(.secondary)
                }
                // The steps are the bar's label, so they're visible and VoiceOver reads the step, not just a
                // percentage (UI Designer, frames 165:1028 and 169:5070).
                ProgressView(value: model.restoreFraction) {
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.restoreStepText)
                }
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
