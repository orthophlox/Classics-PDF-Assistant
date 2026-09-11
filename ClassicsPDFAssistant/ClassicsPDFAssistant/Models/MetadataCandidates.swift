import Foundation

/// Ranked bibliographic-metadata guesses from the `ocr` command's title-page
/// heuristics. Never a single forced answer — RenameSuggestionSheet
/// pre-fills from these but the user edits before applying the filename
/// template. Mirrors `MetadataCandidates` in `backend/pdf_backend/schemas.py`.
struct MetadataCandidates: Codable, Equatable {
    var title: [String] = []
    var author: [String] = []
    var year: [String] = []
}
