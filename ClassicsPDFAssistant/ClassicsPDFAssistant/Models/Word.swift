import Foundation

/// One OCR'd word: mirrors `Word` in `backend/pdf_backend/schemas.py`.
/// `id` is a local-only identity for SwiftUI lists/diffing — not part of
/// the wire format (excluded from CodingKeys, so it just gets a fresh
/// default on decode).
struct Word: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var bbox: BoundingBox
    var confidence: Double

    private enum CodingKeys: String, CodingKey {
        case text, bbox, confidence
    }
}

extension Word {
    /// The OCR-correction view highlights words at or below this confidence
    /// (0-100; Tesseract reports -1 when it has no confidence figure, which
    /// this treats as "needs review" too, since -1 means we don't actually
    /// know how reliable the word is).
    static let lowConfidenceThreshold: Double = 70

    var needsReview: Bool {
        confidence < 0 || confidence < Word.lowConfidenceThreshold
    }
}
