#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Category row of an expense that can be split (#34, D64). iOS: a row that pushes the category list,
    /// or the split editor once split, reading "Split (3)" (Figma 174:247, 174:346). macOS: the category popup
    /// with + next to it, which turns into the split's lines in place (Figma 177:1969, 177:2301).
    struct TransactionCategoryRow: View {
        @Bindable var model: TransactionFormViewModel
        #if os(macOS)
            /// The amount field of the line + or Add Line just added (#34 S42).
            @FocusState private var focusedLine: UUID?
            @State private var requestedFocus: UUID?
        #endif

        var body: some View {
            #if os(iOS)
                NavigationLink(value: model.split == nil ? TransactionFormRoute.category : .split) {
                    LabeledContent("Category", value: model.splitTitle ?? model.categoryName)
                }
                .accessibilityValue(model.splitTitle ?? model.categorySpokenValue)
            #else
                Group {
                    if let split = model.split {
                        SplitInlineLines(model: model, editor: split, focusedLine: $focusedLine) { requestedFocus = $0 }
                    } else {
                        singleCategory
                    }
                }
                // The new line's field exists only after this update, so focus moves on the next one.
                .task(id: requestedFocus) {
                    guard let line = requestedFocus else {
                        return
                    }
                    await Task.yield()
                    focusedLine = line
                    requestedFocus = nil
                }
            #endif
        }

        #if os(macOS)
            private var singleCategory: some View {
                LabeledContent("Category") {
                    HStack {
                        Picker(selection: $model.categoryID) {
                            Label("Uncategorised", systemImage: "questionmark").tag(UUID?.none)
                            CategoryPickerSections(groups: model.categoryGroups)
                        } label: {
                            Text("Category")
                        } currentValueLabel: {
                            Text(model.categoryName)
                                .accessibilityLabel(model.categorySpokenValue)
                        }
                        .labelsHidden()
                        Button {
                            requestedFocus = model.addSplitLine()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Split Across Categories…")
                        .accessibilityLabel("Split Across Categories…")
                    }
                }
            }
        #endif
    }

    #if os(macOS)
        /// The split's lines under Category (Figma 177:2301, 177:2686): "Split (3)" and the status line, then
        /// a category popup, amount, note and − per line, with each line's errors under it, and Add Line.
        /// Categories on other lines are disabled with "Already used on another line" (D117.1).
        struct SplitInlineLines: View {
            let model: TransactionFormViewModel
            let editor: SplitEditorViewModel
            var focusedLine: FocusState<UUID?>.Binding
            /// Moves focus to a line's amount once it's on screen.
            let requestFocus: (UUID) -> Void
            @State private var confirmingRemove = false
            /// A delete of a line that holds refunds, waiting for Delete Line (D112, D220).
            @State private var pendingDelete: SplitConfirmation?

            var body: some View {
                LabeledContent("Category") {
                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        HStack {
                            Text(model.splitTitle ?? "")
                                .bold()
                            Spacer()
                            Text(editor.remainingText)
                                .font(.theme(Typography.MacOS.footnote))
                                .foregroundStyle(remainingTone)
                        }
                        ForEach(editor.lines) { line in
                            lineRow(line.id)
                        }
                        HStack {
                            Button("Add Line") {
                                if let line = editor.addLine() {
                                    requestFocus(line)
                                }
                            }
                            .disabled(!editor.canAddLine)
                            Text("Blank amounts share what’s left. 2–20 lines.")
                                .font(.theme(Typography.MacOS.footnote))
                                .foregroundStyle(Color(ThemeColor.labelSecondary))
                        }
                        // Only while the lines don't add up; line errors show under their lines.
                        if editor.showsUnbalancedFootnote {
                            Text(
                                "Save stays unavailable until the lines add up to the total and every line has a category and an amount above 0. A category can be used on one line only."
                            )
                            .font(.theme(Typography.MacOS.footnote))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Remove Split", role: .destructive) { confirmingRemove = true }
                    }
                }
                .alert(editor.removeSplitConfirmation.title, isPresented: $confirmingRemove) {
                    Button("Remove Split", role: .destructive) { model.removeSplit() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(editor.removeSplitConfirmation.message)
                }
                .alert(
                    pendingDelete?.title ?? "",
                    isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                    presenting: pendingDelete,
                ) { confirmation in
                    Button("Delete Line", role: .destructive) { model.removeSplitLine(confirmation.id) }
                    Button("Cancel", role: .cancel) {}
                } message: { confirmation in
                    Text(confirmation.message)
                }
            }

            /// A line with refunds asks first; any other line goes straight away (D219.4).
            private func delete(_ line: UUID) {
                if let confirmation = editor.deleteConfirmation(for: line) {
                    pendingDelete = confirmation
                } else {
                    model.removeSplitLine(line)
                }
            }

            private var remainingTone: Color {
                if case .over = editor.status {
                    return Color(ThemeColor.statusOverspent)
                }
                return Color(ThemeColor.labelSecondary)
            }

            private func lineRow(_ id: UUID) -> some View {
                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                    HStack {
                        Picker(
                            selection: Binding(
                                get: { editor.category(of: id) },
                                set: { editor.setCategory($0, of: id) },
                            )
                        ) {
                            // An archived current category comes first, selected, then the offered ones.
                            if let archived = editor.archivedCategory(of: id) {
                                Text(archived.name).tag(Optional(archived.id))
                                Divider()
                            }
                            Text("Choose…").tag(UUID?.none)
                            ForEach(editor.categories) { option in
                                let used = editor.isUsedElsewhere(option.id, than: id)
                                VStack(alignment: .leading) {
                                    Text(option.name)
                                    if used {
                                        Text(SplitEditorViewModel.usedElsewhereText)
                                    }
                                }
                                .tag(Optional(option.id))
                                .disabled(used)
                            }
                        } label: {
                            Text("Category")
                        }
                        .labelsHidden()
                        if editor.isAuto(id) {
                            Text("auto")
                                .font(.theme(Typography.MacOS.footnote))
                                .foregroundStyle(Color(ThemeColor.accentDefault))
                        }
                        TextField(
                            "Amount",
                            text: Binding(
                                get: { editor.amountText(of: id) },
                                set: { editor.setAmountText($0, of: id) },
                            ),
                            prompt: Text(editor.amountFigure(of: id)),
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .focused(focusedLine, equals: id)
                        .accessibilityLabel(editor.categoryName(of: id))
                        .accessibilityValue(editor.amountFigure(of: id))
                        TextField(
                            "Note",
                            text: Binding(get: { editor.note(of: id) }, set: { editor.setNote($0, of: id) }),
                            prompt: Text("Note"),
                        )
                        .labelsHidden()
                        .accessibilityHint(editor.categoryName(of: id))
                        Button {
                            delete(id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Line")
                        .accessibilityLabel("Delete Line")
                        .accessibilityValue(editor.categoryName(of: id))
                    }
                    if editor.hasIssues(id) {
                        HStack {
                            ForEach(editor.issues(of: id), id: \.self) { issue in
                                Label(issue, systemImage: "exclamationmark.circle")
                                    .font(.theme(Typography.MacOS.footnote))
                                    .foregroundStyle(Color(ThemeColor.statusOverspent))
                            }
                        }
                    }
                }
            }
        }
    #endif
#endif
