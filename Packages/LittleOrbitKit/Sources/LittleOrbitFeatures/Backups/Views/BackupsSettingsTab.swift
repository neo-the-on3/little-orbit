#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The macOS Settings window's Backups tab (#40): a table of every backup, newest first, with
    /// Restore…, Export…, Delete… and Restore from File…. File > Restore from Backup… opens this tab and its file
    /// panel (`isPickingFile`).
    public struct BackupsSettingsTab: View {
        @Bindable var model: BackupsViewModel
        @Binding var isPickingFile: Bool
        @State private var selection: UUID?

        public init(model: BackupsViewModel, isPickingFile: Binding<Bool>) {
            self.model = model
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
                        if let restored = model.restoredMessage {
                            Label(restored, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color(ThemeColor.statusSuccess))
                        }
                    }
                    Spacer()
                    Button(BackupPresentation.backUpNow) {
                        Task { await model.backUpNow() }
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
                Text(model.presentation.storageFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let id = selection, model.row(id) != nil {
                    Text(model.deleteFootnote(for: id))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.space5)
            .frame(minWidth: 640, minHeight: 420)
            .modifier(BackupFlowModifier(model: model, isPickingFile: $isPickingFile))
            .confirmationDialog(
                BackupPresentation.deleteTitle,
                isPresented: Binding(
                    get: { model.deletePrompt != nil },
                    set: { if !$0 { model.deletePrompt = nil } },
                ),
            ) {
                Button(BackupPresentation.deleteBackup, role: .destructive) {
                    Task { await model.confirmDelete() }
                }
                Button("Cancel", role: .cancel) { model.deletePrompt = nil }
            } message: {
                Text(model.presentation.deleteMessage)
            }
            .task { model.load() }
        }

        @ViewBuilder
        private func actions(for id: UUID) -> some View {
            Button(BackupPresentation.restoreEllipsis) {
                Task { await model.requestRestore(id) }
            }
            .disabled(!model.actionsEnabled)
            Button(BackupPresentation.exportEllipsis) {
                Task { await model.requestExport(id) }
            }
            .disabled(!model.actionsEnabled)
            Button(BackupPresentation.deleteEllipsis, role: .destructive) {
                model.requestDelete(id)
            }
            .disabled(!model.actionsEnabled)
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
