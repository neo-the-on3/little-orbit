#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// Reading is cancellable; saving keeps the existing non-cancellable overlay.
    struct CSVImportWorkingView: View {
        let model: CSVImportViewModel
        let cancelReading: () -> Void

        var body: some View {
            VStack(spacing: 12) {
                if let fraction = model.readingFraction {
                    ProgressView(model.readingCountText ?? model.workingText, value: fraction)
                } else {
                    ProgressView(model.workingText)
                }
                if model.isReading {
                    Button(ImportExportText.cancel, role: .cancel, action: cancelReading)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
    }
#endif
