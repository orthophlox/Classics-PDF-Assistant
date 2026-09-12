import Foundation

/// App-level state for one imported document as it moves through the
/// pipeline. Not part of the wire protocol — assembled from backend
/// responses plus in-progress user edits (crop adjustments, OCR
/// corrections, rename choices).
enum DocumentStatus: Equatable {
    case imported
    case analyzing
    case readyForCrop
    case ocrRunning(pageIndex: Int, totalPages: Int)
    case readyForReview
    case finalizing
    case done(outputs: FinalizeOutputs)
    case error(String)
}

@MainActor
final class DocumentItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let workDir: URL

    @Published var status: DocumentStatus = .imported
    @Published var pages: [PageAnalysis] = []
    @Published var pageOptions: [PageOptions] = []
    @Published var ocrResults: [Int: PageOCRResult] = [:]  // keyed by pageIndex
    @Published var metadataCandidates: MetadataCandidates = MetadataCandidates()
    @Published var selectedAuthor: String = ""
    @Published var selectedTitle: String = ""
    @Published var selectedYear: String = ""
    @Published var exportOptions = FinalizeOptions()

    init(sourceURL: URL, workDir: URL) {
        self.sourceURL = sourceURL
        self.workDir = workDir
    }

    var displayName: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }

    var suggestedOutputBasename: String {
        MetadataFilename.render(author: selectedAuthor, title: selectedTitle, year: selectedYear)
            ?? displayName
    }

    // MARK: - OCR confidence summary

    /// Average of all pages' mean_confidence (backend-computed, from
    /// `ocr`'s response), ignoring pages with no confidence data yet.
    /// nil before any OCR has run.
    var overallConfidence: Double? {
        let values = ocrResults.values.map(\.meanConfidence).filter { $0 >= 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Total low-confidence words across all pages — the same
    /// `Word.needsReview` flag the correction view highlights per page.
    var lowConfidenceWordCount: Int {
        pageOptions.reduce(0) { $0 + $1.words.filter(\.needsReview).count }
    }

    /// Pages with at least one word needing review, sorted by pageIndex.
    var pagesNeedingReview: [Int] {
        pageOptions
            .filter { $0.words.contains(where: \.needsReview) }
            .map(\.pageIndex)
            .sorted()
    }

    /// The page with the lowest mean OCR confidence — the natural first
    /// stop when proofing a long document. nil before OCR has run.
    var worstPageIndex: Int? {
        let withConfidence = ocrResults.filter { $0.value.meanConfidence >= 0 }
        if let worst = withConfidence.min(by: { $0.value.meanConfidence < $1.value.meanConfidence }) {
            return worst.key
        }
        return ocrResults.keys.min()
    }
}

/// Swift-side mirror of `render_filename`/`sanitize_filename` in
/// `backend/pdf_backend/metadata.py`, so the rename sheet can preview the
/// resulting filename live without a round-trip to the backend.
enum MetadataFilename {
    static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?*\"<>|")
            .union(.controlCharacters)
        let cleaned = name.unicodeScalars.filter { !illegal.contains($0) }
        let collapsedWhitespace = String(String.UnicodeScalarView(cleaned))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsedWhitespace.isEmpty ? "untitled" : collapsedWhitespace
    }

    static func render(author: String, title: String, year: String) -> String? {
        var parts: [String] = []
        let author = author.trimmingCharacters(in: .whitespaces)
        let title = title.trimmingCharacters(in: .whitespaces)
        let year = year.trimmingCharacters(in: .whitespaces)

        if !author.isEmpty { parts.append(sanitize(author)) }
        if !title.isEmpty { parts.append(sanitize(title)) }
        guard !parts.isEmpty || !year.isEmpty else { return nil }

        var name = parts.isEmpty ? "Untitled" : parts.joined(separator: " - ")
        if !year.isEmpty {
            name += " (\(sanitize(year)))"
        }
        return name
    }
}
