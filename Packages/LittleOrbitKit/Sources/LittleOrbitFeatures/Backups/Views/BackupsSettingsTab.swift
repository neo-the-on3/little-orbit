#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The macOS Settings window's Backups tab (#40): a table of every backup, newest first, with
    /// Restore…, Export…, Delete… and Restore from File…. File > Restore from Backup… opens this tab and its file
    /// panel (`isPickingFile`).
    ///
    /// It's the root of the Settings window's Backups, so it makes that window's own Backups state: prompts,
    /// alerts and the restore line never show in another window (Tech Architect).
    public struct BackupsSettingsTab: View {
        @State private var window: BackupsWindow
        @Binding var isPickingFile: Bool
        @State private var selection: UUID?

        private var model: BackupsViewModel {
            window.model
        }

        public init(model: BackupsViewModel, isPickingFile: Binding<Bool>) {
            _window = State(initialValue: BackupsWindow(model: model))
            _isPickingFile = isPickingFile
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        if model.isBackingUp {
                            HStack(spacing: Spacing.space2) {
                                ProgressView().controlSize(.small)
                                Text(BackupPresentation.backupInProgress)
                            }
                        } else if let last = model.lastBackupText {
                            Text(last)
                        }
                        if let failure = model.failureMessage {
                            Label(failure, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(ThemeColor.statusOverspent))
                        }
                        if let restored = window.restoredMessage {
                            Label(restored, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color(ThemeColor.statusSuccess))
                        }
                    }
                    Spacer()
                    Button(BackupPresentation.backUpNow) {
                        Task { await window.backUpNow() }
                    }
                    .disabled(!model.actionsEnabled)
                }
                if model.isEmpty {
                    ContentUnavailableView(
                        BackupPresentation.emptyTitle,
                        systemImage: "clock.arrow.circlepath",
                        description: Text(model.presentation.emptyMessage),
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    Table(model.rows, selection: $selection) {
                        TableColumn("Date") { row in
                            Text(row.title).accessibilityLabel(row.accessibilityLabel)
                        }
                        TableColumn("Type", value: \.kindText)
                        TableColumn("Status") { row in
                            // The full text in a tooltip when a narrow window cuts "Made by a newer version of
                            // little-orbit." short (UI Designer).
                            Text(row.statusText ?? "").help(row.statusText ?? "")
                        }
                        TableColumn("Size", value: \.sizeText)
                        TableColumn("Format", value: \.formatText)
                        TableColumn("Accounts") { row in Text(row.accountCount.formatted()) }
                        TableColumn("Transactions") { row in Text(row.transactionCount.formatted()) }
                    }
                    .frame(minHeight: 220)
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let id = ids.first {
                            actions(for: id)
                        }
                    }
                }
                HStack {
                    if let id = selection, model.row(id) != nil {
                        actions(for: id)
                    }
                    Spacer()
                    Button(BackupPresentation.restoreFromFile) { isPickingFile = true }
                        .disabled(!model.actionsEnabled)
                }
                GroupBox(BackupPresentation.keepHeader) {
                    VStack(alignment: .leading, spacing: Spacing.space2) {
                        BackupKeepSteppers(window: window)
                        Text(model.keepFooter)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(model.presentation.storageFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let id = selection, let row = model.row(id) {
                    if let explanation = row.explanation {
                        Label(explanation, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color(ThemeColor.statusWarning))
                    }
                    Text(model.deleteFootnote(for: id))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.space5)
            .frame(minWidth: 640, minHeight: 520)
            .modifier(BackupFlowModifier(window: window, isPickingFile: $isPickingFile))
            .modifier(BackupPruneAlert(window: window))
            .task { await window.load() }
        }

        @ViewBuilder
        private func actions(for id: UUID) -> some View {
            // Disabled for a damaged or newer-format backup; Delete… still works (L29, L35, L43).
            let canRestore = model.row(id)?.canRestore == true
            Button(BackupPresentation.restoreEllipsis) {
                Task { await window.requestRestore(id) }
            }
            .disabled(!model.actionsEnabled || !canRestore)
            Button(BackupPresentation.exportEllipsis) {
                Task { await window.requestExport(id) }
            }
            .disabled(!model.actionsEnabled || !canRestore)
            Button(BackupPresentation.deleteEllipsis, role: .destructive) {
                window.requestDelete(id)
            }
            // Off while the backup is being exported, in any window (D208.1). This covers the context menu too.
            .disabled(!model.deleteEnabled(for: id))
        }
    }

    /// File > Restore from Backup… (S64): opens Settings on the Backups tab with its file panel.
    public struct RestoreFromBackupCommand: Commands {
        @Binding var isPickingFile: Bool
        @Environment(\.openSettings) private var openSettings

        public init(isPickingFile: Binding<Bool>) {
            _isPickingFile = isPickingFile
        }

        public var body: some Commands {
            CommandGroup(after: .importExport) {
                Button(BackupPresentation.restoreFromBackupMenu) {
                    openSettings()
                    isPickingFile = true
                }
            }
        }
    }
#endif
