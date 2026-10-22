#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// A minimal standard Settings screen, opened from the Accounts toolbar. No other ticket owns Settings yet, so
    /// it holds only Advanced > Backups (#40); later settings join this list.
    ///
    /// It's the root of this window's Settings, so it makes the window's own Backups state: on iPad, a prompt in
    /// one window never shows in another (Tech Architect).
    public struct SettingsView: View {
        @State private var window: BackupsWindow
        @Environment(\.dismiss) private var dismiss

        public init(backups: BackupsViewModel) {
            _window = State(initialValue: BackupsWindow(model: backups))
        }

        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            AdvancedSettingsView(window: window)
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
        let window: BackupsWindow

        var body: some View {
            List {
                Section {
                    NavigationLink {
                        BackupsListView(window: window)
                    } label: {
                        LabeledContent("Backups", value: window.model.rows.first?.title ?? "")
                    }
                } footer: {
                    Text(window.model.presentation.advancedFooter)
                }
            }
            .navigationTitle("Advanced")
            .task { await window.load() }
        }
    }

    /// Settings > Advanced > Backups: Back Up Now, Restore from File…, then every backup newest first (S70).
    struct BackupsListView: View {
        let window: BackupsWindow
        @State private var isPickingFile = false
        /// While a backup's detail is pushed, it presents the flow instead of the list (Tester B3).
        @State private var isShowingDetail = false

        private var model: BackupsViewModel {
            window.model
        }

        var body: some View {
            List {
                if let failure = model.failureMessage {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(ThemeColor.statusOverspent))
                    }
                }
                Section {
                    Button(BackupPresentation.backUpNow) {
                        Task { await window.backUpNow() }
                    }
                    .disabled(!model.actionsEnabled)
                    Button(BackupPresentation.restoreFromFile) { isPickingFile = true }
                        .disabled(!model.actionsEnabled)
                } footer: {
                    if let last = model.lastBackupText {
                        Text(last)
                    }
                }
                Section {
                    BackupKeepSteppers(window: window)
                } header: {
                    Text(BackupPresentation.keepHeader)
                } footer: {
                    Text(model.keepFooter)
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
                                BackupDetailView(window: window, id: row.id, isShowing: $isShowingDetail)
                            } label: {
                                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                                    Text(row.title)
                                    Text(row.detailLine)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(row.countsText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let status = row.statusText {
                                        Label(status, systemImage: "exclamationmark.triangle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(Color(ThemeColor.statusWarning))
                                    }
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
            .modifier(BackupFlowModifier(window: window, isPickingFile: $isPickingFile, isActive: !isShowingDetail))
            .modifier(BackupPruneAlert(window: window))
            .task { await window.load() }
        }
    }

    /// One backup: its details, Restore…, Export… and Delete Backup (S61).
    struct BackupDetailView: View {
        let window: BackupsWindow
        let id: UUID
        @Binding var isShowing: Bool
        @Environment(\.dismiss) private var dismiss

        private var model: BackupsViewModel {
            window.model
        }

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
                    // A damaged or newer-format backup has no Restore… or Export… on iOS (L29, L35).
                    if row.canRestore {
                        Section {
                            Button(BackupPresentation.restoreEllipsis) {
                                Task { await window.requestRestore(id) }
                            }
                            Button(BackupPresentation.exportEllipsis) {
                                Task { await window.requestExport(id) }
                            }
                        }
                        .disabled(!model.actionsEnabled)
                    } else if let explanation = row.explanation {
                        Section {
                            Label(explanation, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(ThemeColor.statusWarning))
                        }
                    }
                    Section {
                        Button(BackupPresentation.deleteBackup, role: .destructive) {
                            window.requestDelete(id)
                        }
                        // Off while the backup is being exported, in any window (D208.1).
                        .disabled(!model.deleteEnabled(for: id))
                    } footer: {
                        Text(model.deleteFootnote(for: id))
                    }
                }
                .navigationTitle(BackupPresentation.detailTitle)
                .navigationBarTitleDisplayMode(.inline)
                // Restore…, Export… and Delete Backup present here, over the detail (Tester B3).
                .modifier(BackupFlowModifier(window: window, isPickingFile: .constant(false)))
                .onAppear { isShowing = true }
                .onDisappear { isShowing = false }
            } else {
                // Deleted, or replaced by a restore: go back to the list.
                Color.clear.onAppear { dismiss() }
            }
        }
    }
#endif
