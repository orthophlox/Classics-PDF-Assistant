import Foundation

/// Request bodies for the four backend commands. See docs/JSON_PROTOCOL.md —
/// `command` is redundant with the CLI argument but included in the body
/// too, matching the documented wire shape exactly.

struct AnalyzeRequest: Encodable {
    var command = "analyze"
    var inputPdf: String
    var workDir: String
    var options: AnalyzeOptions
}

struct OCRRequest: Encodable {
    var command = "ocr"
    var inputPdf: String
    var workDir: String
    var languages: [String]
    var options: AnalyzeOptions
    var pages: [PageOptions]
}

struct FinalizeRequest: Encodable {
    var command = "finalize"
    var inputPdf: String
    var workDir: String
    var outputBasename: String
    var outputDir: String
    var options: FinalizeOptions
    var pages: [PageOptions]
}

struct BatchDocumentSpec: Encodable {
    var inputPdf: String
    var outputDir: String
    var autoRename: Bool
}

struct BatchRequest: Encodable {
    var command = "batch"
    var documents: [BatchDocumentSpec]
    var languages: [String]
    var options: FinalizeOptions
}
