import Foundation

/// One line of NDJSON progress streamed on the backend subprocess's stderr
/// while `ocr`/`finalize`/`batch` run. See docs/JSON_PROTOCOL.md.
struct ProgressEvent: Codable {
    var event: String  // "page_progress" | "document_progress"
    var document: String?
    var pageIndex: Int?
    var totalPages: Int?
    var stage: String?  // "analyze" | "ocr" | "finalize", for page_progress
    var index: Int?
    var totalDocuments: Int?
}
