#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// The description field (D55, D111). It shows exactly the text the model kept, so typing visibly stops
    /// at 100 characters instead of the field running on and Save cutting it (Tester's #87 B2). A paste is
    /// cut by the model, with its note, and the field shows the cut text.
    struct LimitedDescriptionField: View {
        /// The model's description.
        let text: String
        let axis: Axis
        /// The label is hidden, as in bulk edit, where the hidden label alone names the field for VoiceOver.
        /// An accessibilityLabel on top of a hidden label reads "Description, Description" (#110).
        let hidesLabel: Bool
        /// Applies an edit and returns the text to show.
        let update: (String) -> String
        @State private var shown = ""

        init(
            text: String,
            axis: Axis = .horizontal,
            hidesLabel: Bool = false,
            update: @escaping (String) -> String,
        ) {
            self.text = text
            self.axis = axis
            self.hidesLabel = hidesLabel
            self.update = update
        }

        var body: some View {
            field
                .onAppear { shown = text }
                .onChange(of: shown) { _, newValue in
                    let kept = update(newValue)
                    if kept != newValue {
                        // Resetting the state, not only the model, is what puts the field back (#87 B2).
                        shown = kept
                    }
                }
                .onChange(of: text) { _, newValue in
                    // A chosen suggestion, or an edit loaded later.
                    if newValue != shown {
                        shown = newValue
                    }
                }
        }

        @ViewBuilder private var field: some View {
            let field = TextField("Description", text: $shown, prompt: Text("Description"), axis: axis)
            if hidesLabel {
                field.labelsHidden()
            } else {
                field.accessibilityLabel("Description")
            }
        }
    }
#endif
