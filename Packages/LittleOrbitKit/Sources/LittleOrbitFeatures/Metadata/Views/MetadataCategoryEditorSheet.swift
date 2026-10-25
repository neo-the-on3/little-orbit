#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac Edit Category sheet (#24 design, Mac Edit Category): Name, a read-only Kind, a read-only
    /// Parent for a subcategory (the Mac has no Parent control, D287.1), Icon from a grid popover, and Colour
    /// for a top-level category only (D298). Return saves; Esc, like Cancel, asks “Discard Changes?” when
    /// something was entered or changed (D300.1). A name error shows under the name field (D295.4).
    struct MetadataCategoryEditorSheet: View {
        @Bindable var model: CategoryEditorViewModel
        let screen: CategoriesViewModel
        @State private var isPickingIcon = false
        @State private var isConfirmingDiscard = false
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.title)
                    .font(.headline)
                Form {
                    TextField(MetadataText.nameLabel, text: $model.name)
                    if let error = model.nameError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    LabeledContent(MetadataText.kindLabel, value: model.kindValue)
                    if model.isSubcategory, let parent = model.parentID.flatMap(screen.category) {
                        LabeledContent(MetadataText.parentLabel, value: parent.name)
                    }
                    LabeledContent(MetadataText.iconLabel) {
                        Button {
                            isPickingIcon = true
                        } label: {
                            Label(model.symbolLabel, systemImage: model.symbolName)
                        }
                        .popover(isPresented: $isPickingIcon, arrowEdge: .bottom) {
                            MetadataIconGrid(model: model) { isPickingIcon = false }
                        }
                    }
                    if !model.isSubcategory {
                        colourPicker
                    }
                }
                .formStyle(.columns)
                Text(model.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(CategoryText.cancel) { cancel() }
                        .keyboardShortcut(.cancelAction)
                    Button(CategoryText.save) {
                        if model.save() {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
                }
            }
            .padding(20)
            .frame(width: 460)
            .confirmationDialog(DiscardText.title, isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button(DiscardText.discard, role: .destructive) { dismiss() }
                Button(DiscardText.keepEditing, role: .cancel) {}
            }
            .alert(
                model.alert?.title ?? "",
                isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                presenting: model.alert,
            ) { _ in
                Button(CategoryText.okay) { model.alert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }

        private var colourPicker: some View {
            Picker(MetadataText.colourLabel, selection: $model.hue) {
                ForEach(CategoryHue.allCases, id: \.self) { hue in
                    Label {
                        Text(model.colourName(hue))
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(Color(hue.token))
                            .accessibilityHidden(true)
                    }
                    .tag(hue)
                }
            }
            .pickerStyle(.menu)
        }

        /// With nothing entered or changed, Cancel closes the sheet; otherwise it asks first (D300.1).
        private func cancel() {
            if model.hasUnsavedEdits {
                isConfirmingDiscard = true
            } else {
                dismiss()
            }
        }
    }

    /// The Icon popover (#24 design, Mac icon picker): every icon with its name, which is also its VoiceOver
    /// label. An icon an earlier version saved that isn't in the list shows first as “Current Icon”.
    struct MetadataIconGrid: View {
        @Bindable var model: CategoryEditorViewModel
        let onPick: () -> Void
        private let columns = Array(repeating: GridItem(.fixed(64), spacing: 8), count: 8)

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.symbolOptions) { option in
                        let isSelected = option.symbol == model.symbolName
                        Button {
                            model.symbolName = option.symbol
                            onPick()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: option.symbol)
                                    .font(.title3)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.accentColor, lineWidth: 2)
                                        }
                                    }
                                Text(option.name)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(width: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(option.name)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(option.name)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                Text(MetadataText.iconFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 8 * 64 + 7 * 8 + 32)
        }
    }
#endif
