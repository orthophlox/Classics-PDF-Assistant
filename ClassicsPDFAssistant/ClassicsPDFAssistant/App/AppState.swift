import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var documents: [DocumentItem] = []
    @Published var selectedDocumentID: DocumentItem.ID?

    // Settings — defaults to all three languages on, since mixed grc/lat/eng
    // documents are the primary use case this app is built for.
    @AppStorage("useGreek") var useGreek: Bool = true
    @AppStorage("useLatin") var useLatin: Bool = true
    @AppStorage("useEnglish") var useEnglish: Bool = true
    @AppStorage("dpi") var dpi: Int = 300
    @AppStorage("computeConfidence") var computeConfidence: Bool = true
    @AppStorage("defaultOutputDirectory") private var defaultOutputDirectoryPath: String = ""

    private let backend = BackendService()

    var selectedLanguages: [String] {
        var langs: [String] = []
        if useGreek { langs.append("grc") }
        if useLatin { langs.append("lat") }
        if useEnglish { langs.append("eng") }
        return langs.isEmpty ? ["eng"] : langs
    }

    var defaultOutputDirectory: URL {
        get {
            if defaultOutputDirectoryPath.isEmpty {
                return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
            }
            return URL(fileURLWithPath: defaultOutputDirectoryPath)
        }
        set { defaultOutputDirectoryPath = newValue.path }
    }

    var selectedDocument: DocumentItem? {
        documents.first { $0.id == selectedDocumentID }
    }

    // MARK: - Import

    func importDocuments(at urls: [URL]) {
        for url in urls {
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClassicsPDFAssistant", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let item = DocumentItem(sourceURL: url, workDir: workDir)
            documents.append(item)
            if selectedDocumentID == nil { selectedDocumentID = item.id }
            Task { await analyze(item) }
        }
    }

    /// Imports every PDF found directly inside a folder, for the batch flow's
    /// "add a folder" entry point (DocumentListView).
    func importFolder(at folderURL: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        let pdfs = entries.filter { $0.pathExtension.lowercased() == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        importDocuments(at: pdfs)
    }

    // MARK: - Pipeline stages

    func analyze(_ item: DocumentItem) async {
        item.status = .analyzing
        do {
            try FileManager.default.createDirectory(at: item.workDir, withIntermediateDirectories: true)
            let request = AnalyzeRequest(
                inputPdf: item.sourceURL.path,
                workDir: item.workDir.path,
                options: AnalyzeOptions(dpi: dpi, deskew: true, autoCrop: true, cropPaddingPt: 12)
            )
            let response: AnalyzeResponse = try await backend.run(command: "analyze", request: request) { _ in }
            item.pages = response.pages
            item.pageOptions = response.pages.map {
                PageOptions(pageIndex: $0.pageIndex, cropBox: $0.detectedCropBox, deskewAngleDeg: $0.skewAngleDeg)
            }
            item.status = .readyForCrop
        } catch {
            item.status = .error(error.localizedDescription)
        }
    }

    /// Called once the user has reviewed/adjusted crop boxes in
    /// CropOverlayView and is ready to pay the OCR cost.
    func runOCR(_ item: DocumentItem) async {
        do {
            let request = OCRRequest(
                inputPdf: item.sourceURL.path,
                workDir: item.workDir.path,
                languages: selectedLanguages,
                options: AnalyzeOptions(dpi: dpi),
                pages: item.pageOptions
            )
            let totalPages = item.pageOptions.count
            let response: OCRResponse = try await backend.run(command: "ocr", request: request) { event in
                guard event.event == "page_progress", let pageIndex = event.pageIndex else { return }
                Task { @MainActor in
                    item.status = .ocrRunning(pageIndex: pageIndex, totalPages: event.totalPages ?? totalPages)
                }
            }
            for result in response.pages {
                item.ocrResults[result.pageIndex] = result
                if let idx = item.pageOptions.firstIndex(where: { $0.pageIndex == result.pageIndex }) {
                    item.pageOptions[idx].words = result.words
                }
            }
            item.metadataCandidates = response.metadataCandidates
            item.selectedAuthor = response.metadataCandidates.author.first ?? ""
            item.selectedTitle = response.metadataCandidates.title.first ?? ""
            item.selectedYear = response.metadataCandidates.year.first ?? ""
            item.status = .readyForReview
        } catch {
            item.status = .error(error.localizedDescription)
        }
    }

    /// Called from ExportOptionsView once the user has corrected any
    /// low-confidence OCR words and confirmed the rename suggestion.
    func finalizeDocument(_ item: DocumentItem, outputDirectory: URL) async {
        item.status = .finalizing
        do {
            let request = FinalizeRequest(
                inputPdf: item.sourceURL.path,
                workDir: item.workDir.path,
                outputBasename: item.suggestedOutputBasename,
                outputDir: outputDirectory.path,
                options: item.exportOptions,
                pages: item.pageOptions
            )
            let response: FinalizeResponse = try await backend.run(command: "finalize", request: request) { _ in }
            item.status = .done(outputs: response.outputs ?? FinalizeOutputs())
        } catch {
            item.status = .error(error.localizedDescription)
        }
    }

    func cancelCurrentOperation() async {
        await backend.cancelCurrent()
    }

    // MARK: - Cleanup

    func removeDocument(_ item: DocumentItem) {
        documents.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.workDir)
        if selectedDocumentID == item.id {
            selectedDocumentID = documents.first?.id
        }
    }
}
