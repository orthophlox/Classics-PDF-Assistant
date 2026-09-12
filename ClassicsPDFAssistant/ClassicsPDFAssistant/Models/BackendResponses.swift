import Foundation

/// Every backend response shares this `status`/`error` envelope shape —
/// BackendService checks it uniformly before handing back the
/// command-specific payload. See docs/JSON_PROTOCOL.md "Error shape".
protocol BackendResponseEnvelope: Decodable {
    var status: String { get }
    var error: String? { get }
}

struct PageAnalysis: Codable, Identifiable {
    var id: Int { pageIndex }
    var pageIndex: Int
    var previewImage: String
    var skewAngleDeg: Double
    var detectedCropBox: BoundingBox
    var imageWidth: Int
    var imageHeight: Int
    /// Full region classification (main text / apparatus / margins / other)
    /// for critical editions — detectedCropBox is always the main_text
    /// region's box; this is the richer data the crop-review UI displays.
    /// See docs/ARCHITECTURE.md "Multi-region detection".
    var detectedRegions: [Region] = []
}

struct AnalyzeResponse: BackendResponseEnvelope {
    var status: String
    var error: String?
    var pages: [PageAnalysis] = []
}

struct PageOCRResult: Codable, Identifiable {
    var id: Int { pageIndex }
    var pageIndex: Int
    var words: [Word]
    var meanConfidence: Double
}

struct OCRResponse: BackendResponseEnvelope {
    var status: String
    var error: String?
    var pages: [PageOCRResult] = []
    var metadataCandidates: MetadataCandidates = MetadataCandidates()
}

struct FinalizeOutputs: Codable, Equatable {
    var searchablePdf: String?
    var plainText: String?
    var pdfA: String?
}

struct FinalizeResponse: BackendResponseEnvelope {
    var status: String
    var error: String?
    var outputs: FinalizeOutputs?
}

struct BatchDocumentResult: Codable, Identifiable {
    var id: String { inputPdf }
    var inputPdf: String
    var status: String
    var outputs: FinalizeOutputs?
    var error: String?
    /// Average OCR confidence across the document's pages — batch mode has
    /// no interactive review step, so this is the only signal available for
    /// "does this one need a closer look?" without opening it.
    var meanConfidence: Double?
}

struct BatchResponse: BackendResponseEnvelope {
    var status: String
    var error: String?
    var documents: [BatchDocumentResult] = []
}
