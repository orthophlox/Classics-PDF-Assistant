import Foundation

/// Mirrors `AnalyzeOptions` in `backend/pdf_backend/schemas.py`.
struct AnalyzeOptions: Codable, Equatable {
    var dpi: Int = 300
    var deskew: Bool = true
    var autoCrop: Bool = true
    var cropPaddingPt: Double = 12.0
}

/// Mirrors `FinalizeOptions` in `backend/pdf_backend/schemas.py`.
struct FinalizeOptions: Codable, Equatable {
    var dpi: Int = 300
    var searchablePdf: Bool = true
    var plainText: Bool = false
    var pdfA: Bool = false
}

/// Per-page input for the `ocr`/`finalize` commands: overrides layered on
/// the analyze defaults. Mirrors `PageOptions` in `backend/pdf_backend/schemas.py`.
struct PageOptions: Codable, Equatable {
    var pageIndex: Int
    var cropBox: BoundingBox?
    var deskewAngleDeg: Double?
    var words: [Word] = []
}
