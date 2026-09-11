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
}

struct BatchResponse: BackendResponseEnvelope {
    var status: String
    var error: String?
    var documents: [BatchDocumentResult] = []
}
