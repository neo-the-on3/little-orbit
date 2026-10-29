import Foundation

/// The wording for a file opened from outside the app (#189, D387.4).
extension ImportExportText {
    static var finishImportFirstTitle: String {
        FeatureText.string(
            "Finish This Import First",
            comment:
                "Alert title when a CSV file is opened from outside the app while another import is open past its file step (D387.4). The only button is OK.",
        )
    }

    static func finishImportFirst(current: String, new: String) -> String {
        FeatureText.format("Finish or cancel the import of “%1$@”, then open “%2$@” again.", current, new)
    }

    static var oneFileAtATimeTitle: String {
        FeatureText.string(
            "Import One File at a Time",
            comment:
                "Mac alert title when several files are dropped on the app at once (D387.4). The only button is OK.",
        )
    }

    static var oneFileAtATime: String {
        FeatureText.string(
            "Drop a single file to import it. Nothing was imported.",
            comment: "Mac alert message when several files are dropped on the app at once (D387.4).",
        )
    }
}
