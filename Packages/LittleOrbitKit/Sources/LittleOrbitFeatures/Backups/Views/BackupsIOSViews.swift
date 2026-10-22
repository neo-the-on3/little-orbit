#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// A minimal standard Settings screen, opened from the Accounts toolbar. No other ticket owns Settings yet, so
    /// it holds only Advanced > Backups (#40); later settings join this list.
    public struct SettingsView: View {
        let backups: BackupsViewModel
        @Environment(\.dismiss) private var dismiss

        public init(backups: BackupsViewModel) {
            self.backups = backups
        }

        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            AdvancedSettingsView(backups: backups)
                        } label: {
                            Label("Advanced", systemImage: "gearshape.2")
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    /// Settings > Advanced, with the Backups row and its last-backup time.
    struct AdvancedSettingsView: View {
        let backups: BackupsViewModel

        var body: some View {
            List {
                Section {
                    NavigationLink {
                        BackupsListView(model: backups)
                    } label: {
                        LabeledContent("Backups", value: backups.rows.first?.title ?? "")
                    }
                } footer: {
                    Text(backups.presentation.advancedFooter)
                }
            }
            .navigationTitle("Advanced")
            .task { backups.load() }
        }
    }

    /// Settings > Advanced > Backups: Back Up Now, Restore from File…, then every backup newest first (S70).
    public struct BackupsListView: View {
        @Bindable var model: BackupsViewModel
        @State private var isPickingFile = false

        public init(model: BackupsViewModel) {
            self.model = model
        }

        public var body: some View {
            List {
                if let failure = model.failureMessage {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(ThemeColor.statusOverspent))
                    }
                }
                Section {
                    Button(BackupPresentation.backUpNow) {
                        Task { await model.backUpNow() }
                    }
                    .disabled(!model.actionsEnabled)
                    Button(BackupPresentation.restoreFromFile) { isPickingFile = true }
                        .disabled(!model.actionsEnabled)
                } footer: {
                    if let last = model.lastBackupText {
                        Text(last)
                    }
                }
                if model.isBackingUp {
                    // Indeterminate: a single write has no real percentage (D179.2).
                    Section {
                        HStack(spacing: Spacing.space3) {
                            ProgressView()
                            Text(BackupPresentation.backupInProgress)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if model.isEmpty {
                    ContentUnavailableView(
                        BackupPresentation.emptyTitle,
                        systemImage: "clock.arrow.circlepath",
                        description: Text(model.presentation.emptyMessage),
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(model.rows) { row in
                            NavigationLink {
                                BackupDetailView(model: model, id: row.id)
                            } label: {
                                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                                    Text(row.title)
                                    Text(row.detailLine)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(row.countsText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(row.accessibilityLabel)
                            }
                        }
                    } header: {
                        Text("Backups")
                    } footer: {
                        Text(model.presentation.storageFooter)
                    }
                }
            }
            .navigationTitle("Backups")
            .modifier(BackupFlowModifier(model: model, isPickingFile: $isPickingFile))
            .task { model.load() }
        }
    }

    /// One backup: its details, Restore…, Export… and Delete Backup (S61).
    struct BackupDetailView: View {
        @Bindable var model: BackupsViewModel
        let id: UUID
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            if let row = model.row(id) {
                List {
                    Section {
                        LabeledContent("Date", value: row.title)
                        LabeledContent("Type", value: row.kindText)
                        LabeledContent("Size", value: row.sizeText)
                        LabeledContent("Format", value: BackupPresentation.version(row.formatVersion))
                        LabeledContent("Accounts", value: row.accountCount.formatted())
                        LabeledContent("Transactions", value: row.transactionCount.formatted())
                        if row.attachmentCount > 0 {
                            LabeledContent("Attachments", value: row.attachmentCount.formatted())
                        }
                    }
                    Section {
                        Button(BackupPresentation.restoreEllipsis) {
                            Task { await model.requestRestore(id) }
                        }
                        Button(BackupPresentation.exportEllipsis) {
                            Task { await model.requestExport(id) }
                        }
                    }
                    .disabled(!model.actionsEnabled)
                    Section {
                        Button(BackupPresentation.deleteBackup, role: .destructive) {
                            model.requestDelete(id)
                        }
                        .disabled(!model.actionsEnabled)
                    } footer: {
                        Text(model.deleteFootnote(for: id))
                    }
                }
                .navigationTitle(BackupPresentation.detailTitle)
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog(
                    BackupPresentation.deleteTitle,
                    isPresented: Binding(
                        get: { model.deletePrompt != nil },
                        set: { if !$0 { model.deletePrompt = nil } },
                    ),
                    titleVisibility: .visible,
                ) {
                    Button(BackupPresentation.deleteBackup, role: .destructive) {
                        Task { await model.confirmDelete() }
                    }
                    Button("Cancel", role: .cancel) { model.deletePrompt = nil }
                } message: {
                    Text(model.presentation.deleteMessage)
                }
            } else {
                // Deleted, or replaced by a restore: go back to the list.
                Color.clear.onAppear { dismiss() }
            }
        }
    }
#endif
