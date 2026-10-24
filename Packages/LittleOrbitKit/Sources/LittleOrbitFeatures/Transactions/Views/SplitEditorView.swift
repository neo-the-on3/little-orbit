#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The screens the iOS entry sheet pushes for an expense's category (#34).
    enum TransactionFormRoute: Hashable {
        /// The category list with "Split Across Categories…" (Figma 174:247).
        case category
        /// The split editor (Figma 174:433).
        case split
    }

    /// The pushed screen for `route`.
    struct TransactionFormDestination: View {
        let route: TransactionFormRoute
        let model: TransactionFormViewModel
        @Binding var path: [TransactionFormRoute]

        var body: some View {
            switch route {
            case .category:
                TransactionCategoryScreen(model: model, path: $path)
            case .split:
                SplitEditorView(model: model, path: $path)
            }
        }
    }

    /// The expense's category list: "Split Across Categories…" with its footnote, then the expense
    /// categories. Picking one goes back to the sheet.
    struct TransactionCategoryScreen: View {
        @Bindable var model: TransactionFormViewModel
        @Binding var path: [TransactionFormRoute]

        var body: some View {
            List {
                // Hidden once a refund is linked, even while this screen is open (D248.1, hide, don't disable).
                if model.offersSplit {
                    Section {
                        NavigationLink("Split Across Categories…", value: TransactionFormRoute.split)
                    } footer: {
                        Text(model.splitOfferFootnote)
                    }
                }
                // Uncategorised stands on its own at the top of the categories, as in the #87 picker.
                Section {
                    row(name: TransactionText.uncategorised, symbol: "questionmark", id: nil)
                }
                Section(model.splitCategoriesHeader) {
                    ForEach(model.categoryOptions) { option in
                        row(name: option.name, symbol: option.symbolName, id: option.id)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
        }

        private func row(name: String, symbol: String, id: UUID?) -> some View {
            Button {
                model.categoryID = id
                path.removeAll()
            } label: {
                HStack {
                    Label(name, systemImage: symbol)
                        .foregroundStyle(Color(ThemeColor.labelPrimary))
                    Spacer()
                    if model.categoryID == id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color(ThemeColor.accentDefault))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(model.categoryID == id ? .isSelected : [])
        }
    }

    /// The split editor (Figma 174:433–174:718): Total, how the lines stand against it, the lines with their
    /// own errors, Add Line and Remove Split. Done applies the lines to the sheet and stays unavailable until
    /// they add up (D64, D117.6); back leaves the sheet as it was.
    struct SplitEditorView: View {
        let model: TransactionFormViewModel
        @Binding var path: [TransactionFormRoute]
        /// A copy of the sheet's lines; Done applies it.
        @State private var editor: SplitEditorViewModel
        @State private var choosingCategoryFor: LineID?
        @State private var confirmingRemove = false
        /// A delete of a line that holds refunds, waiting for Delete Line (D112, D220).
        @State private var pendingDelete: SplitConfirmation?
        /// The line whose Amount has focus; a new line gets it (UI Designer, 23 Oct).
        @FocusState private var focusedLine: UUID?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        /// The Amount field's width beside the category: room for "₹1,00,000.00" at the body size, scaled with
        /// Dynamic Type, so the field never takes the row from the category (UI Designer's line-row spec).
        @ScaledMetric(relativeTo: .body) private var amountWidth: Double = 128

        init(model: TransactionFormViewModel, path: Binding<[TransactionFormRoute]>) {
            self.model = model
            _path = path
            _editor = State(initialValue: model.makeSplitEditor())
        }

        struct LineID: Identifiable, Hashable {
            let id: UUID
        }

        var body: some View {
            List {
                Section {
                    LabeledContent("Total", value: editor.totalText)
                }
                Section {
                    status
                }
                Section {
                    ForEach(editor.lines) { line in
                        lineRow(line.id)
                            // "Delete Line", as the macOS − reads (D242), not the system "Delete".
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete Line", role: .destructive) { delete(line.id) }
                            }
                    }
                } header: {
                    Text(editor.linesHeader)
                }
                Section {
                    Button("Add Line") {
                        if let line = editor.addLine() {
                            focusedLine = line
                        }
                    }
                    .disabled(!editor.canAddLine)
                } footer: {
                    Text(SplitEditorViewModel.footnote)
                }
                Section {
                    Button("Remove Split", role: .destructive) {
                        confirmingRemove = true
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.applySplit(editor)
                        path.removeAll()
                    }
                    .disabled(!editor.canFinish)
                }
            }
            .navigationDestination(item: $choosingCategoryFor) { line in
                SplitLineCategoryScreen(editor: editor, line: line.id, header: model.splitCategoriesHeader)
            }
            .alert(editor.removeSplitConfirmation.title, isPresented: $confirmingRemove) {
                Button("Remove Split", role: .destructive) {
                    model.removeSplit(editor)
                    path.removeAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(editor.removeSplitConfirmation.message)
            }
            .alert(
                pendingDelete?.title ?? "",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete,
            ) { confirmation in
                Button("Delete Line", role: .destructive) { editor.removeLine(confirmation.id) }
                Button("Cancel", role: .cancel) {}
            } message: { confirmation in
                Text(confirmation.message)
            }
        }

        /// A line with refunds asks first; any other line goes straight away (D219.4).
        private func delete(_ id: UUID) {
            if let confirmation = editor.deleteConfirmation(for: id) {
                pendingDelete = confirmation
            } else {
                editor.removeLine(id)
            }
        }

        /// "Lines add up to the total ₹0.00 left", "₹5.00 left to assign ₹5.00", or the over message and "−₹5.00",
        /// each with its own symbol, so the state isn't shown by colour alone. At accessibility sizes it stacks,
        /// as the transaction rows do, and the figure stays one unit on one line.
        private var status: some View {
            let (symbol, tone) = statusStyle
            let title = Label {
                Text(editor.statusTitle)
            } icon: {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tone)
            // The title already names the amount unless the lines balance, so VoiceOver reads it once.
            let figure = Text(editor.statusFigure)
                .bold()
                .foregroundStyle(tone)
                .accessibilityHidden(editor.status != .balanced)
            return Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        title
                            .fixedSize(horizontal: false, vertical: true)
                        figure
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: Spacing.space2)
                        figure
                            .lineLimit(1)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }

        private var statusStyle: (String, Color) {
            switch editor.status {
            case .balanced: ("checkmark.circle", Color(ThemeColor.labelSecondary))
            case .leftToAssign: ("exclamationmark.circle", Color(ThemeColor.statusWarning))
            case .over: ("exclamationmark.triangle", Color(ThemeColor.statusOverspent))
            }
        }

        private func lineRow(_ id: UUID) -> some View {
            let hasIssues = editor.hasIssues(id)
            let stacked = dynamicTypeSize.isAccessibilitySize
            // The label fills the button's frame, so the whole area is tappable, at least 44 pt tall.
            let category = Button {
                choosingCategoryFor = LineID(id: id)
            } label: {
                Text(editor.categoryName(of: id))
                    .lineLimit(stacked ? nil : 1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: Layout.minimumTargetIOS, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(ThemeColor.labelPrimary))
            let amount = TextField(
                "Amount",
                text: Binding(get: { editor.amountText(of: id) }, set: { editor.setAmountText($0, of: id) }),
                prompt: Text(editor.amountFigure(of: id)),
            )
            .keyboardType(.decimalPad)
            .lineLimit(1)
            .foregroundStyle(Color(hasIssues ? ThemeColor.statusOverspent : ThemeColor.labelPrimary))
            .focused($focusedLine, equals: id)
            .accessibilityLabel(editor.categoryName(of: id))
            .accessibilityValue(editor.amountFigure(of: id))
            return VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                // Stacked at accessibility sizes, as the transaction rows are, so the amount keeps the full width.
                // Otherwise one row: the category takes the flexible space, one line with tail truncation, and
                // the Amount field keeps its own width on the trailing side (UI Designer's line-row spec; a
                // greedy TextField with the higher priority squeezed the category to zero width, Tester's finding).
                if stacked {
                    category
                        .fixedSize(horizontal: false, vertical: true)
                    amount
                        .minimumScaleFactor(0.5)
                } else {
                    HStack(spacing: Spacing.space2) {
                        category
                            .layoutPriority(1)
                        amount
                            .multilineTextAlignment(.trailing)
                            .frame(width: amountWidth)
                    }
                }
                TextField(
                    "Note",
                    text: Binding(get: { editor.note(of: id) }, set: { editor.setNote($0, of: id) }),
                    prompt: Text("Note"),
                )
                .font(.theme(Typography.IOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
                .accessibilityHint(editor.categoryName(of: id))
                ForEach(editor.issues(of: id), id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.circle")
                        .font(.theme(Typography.IOS.footnote))
                        .foregroundStyle(Color(ThemeColor.statusOverspent))
                }
            }
        }
    }

    /// One line's category (Figma 174:826): the expense or income categories, with those on other lines disabled and
    /// marked "Already used on another line" (D117.1). The line's own category keeps its checkmark.
    struct SplitLineCategoryScreen: View {
        let editor: SplitEditorViewModel
        let line: UUID
        let header: String
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            List {
                Section(header) {
                    ForEach(editor.categories) { option in
                        let used = editor.isUsedElsewhere(option.id, than: line)
                        Button {
                            editor.setCategory(option.id, of: line)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                                    Label(option.name, systemImage: option.symbolName)
                                    if used {
                                        Text(SplitEditorViewModel.usedElsewhereText)
                                            .font(.theme(Typography.IOS.footnote))
                                    }
                                }
                                Spacer()
                                if editor.category(of: line) == option.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(ThemeColor.accentDefault))
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(used)
                        .accessibilityAddTraits(editor.category(of: line) == option.id ? .isSelected : [])
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
#endif
