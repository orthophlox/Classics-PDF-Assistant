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

    // Watched-folder auto-processing settings.
    @AppStorage("watchedFolderPath") private var watchedFolderPath: String = ""
    @AppStorage("watchedFolderOutputPath") private var watchedFolderOutputPath: String = ""
    @AppStorage("watchedFolderSeenFiles") private var watchedFolderSeenFilesData: Data = Data()
    @Published var isWatchingFolder = false
    @Published var watchedFolderActivity: [WatchedFolderActivityItem] = []

    private let backend = BackendService()
    private let folderWatcher = FolderWatcher()

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

    // MARK: - Watched folder

    var watchedFolderURL: URL? {
        get { watchedFolderPath.isEmpty ? nil : URL(fileURLWithPath: watchedFolderPath) }
        set { watchedFolderPath = newValue?.path ?? "" }
    }

    var watchedFolderOutputURL: URL {
        get { watchedFolderOutputPath.isEmpty ? defaultOutputDirectory : URL(fileURLWithPath: watchedFolderOutputPath) }
        set { watchedFolderOutputPath = newValue.path }
    }

    private var watchedFolderSeenFiles: [String] {
        get { (try? JSONDecoder().decode([String].self, from: watchedFolderSeenFilesData)) ?? [] }
        set {
            // Cap growth so this doesn't accumulate forever in UserDefaults
            // across months of unattended use — only recency matters here,
            // since the point is just "don't reprocess this specific file
            // again after a relaunch."
            let capped = newValue.suffix(500)
            watchedFolderSeenFilesData = (try? JSONEncoder().encode(Array(capped))) ?? Data()
        }
    }

    /// Starts (or restarts) watching `watchedFolderURL`. No-op if that's unset.
    func startWatchingFolder() {
        guard let folder = watchedFolderURL else { return }
        folderWatcher.start(folder: folder, alreadySeen: Set(watchedFolderSeenFiles)) { [weak self] url in
            Task { @MainActor in
                self?.processWatchedFile(url)
            }
        }
        isWatchingFolder = true
    }

    func stopWatchingFolder() {
        folderWatcher.stop()
        isWatchingFolder = false
    }

    /// Runs the same unattended pipeline as batch mode (auto-detected crop/
    /// deskew, no manual review) on one newly-discovered file, logging the
    /// outcome to `watchedFolderActivity` for the settings UI to show.
    private func processWatchedFile(_ url: URL) {
        watchedFolderSeenFiles.append(url.path)

        let activityID = UUID()
        watchedFolderActivity.insert(
            WatchedFolderActivityItem(id: activityID, fileName: url.lastPathComponent, date: Date(), status: .processing),
            at: 0
        )

        Task {
            let request = BatchRequest(
                documents: [BatchDocumentSpec(inputPdf: url.path, outputDir: watchedFolderOutputURL.path, autoRename: true)],
                languages: selectedLanguages,
                options: FinalizeOptions(dpi: dpi, searchablePdf: true, plainText: false, pdfA: false, bw: false)
            )
            do {
                let response: BatchResponse = try await backend.run(command: "batch", request: request) { _ in }
                let outcome = response.documents.first
                updateWatchedActivity(activityID) { item in
                    if let outcome, outcome.status == "ok" {
                        item.status = .done(meanConfidence: outcome.meanConfidence)
                    } else {
                        item.status = .failed(outcome?.error ?? "Unknown error")
                    }
                }
            } catch {
                updateWatchedActivity(activityID) { $0.status = .failed(error.localizedDescription) }
            }
        }
    }

    private func updateWatchedActivity(_ id: UUID, _ mutate: (inout WatchedFolderActivityItem) -> Void) {
        guard let idx = watchedFolderActivity.firstIndex(where: { $0.id == id }) else { return }
        mutate(&watchedFolderActivity[idx])
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
