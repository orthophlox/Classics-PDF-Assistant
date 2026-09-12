import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            DocumentListView(isImporterPresented: $isImporterPresented)
        } detail: {
            if let document = appState.selectedDocument {
                DocumentDetailView(document: document)
                    .id(document.id)
            } else {
                emptyState
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appState.importDocuments(at: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importPDFRequested)) { _ in
            isImporterPresented = true
        }
        // Drag a PDF (or several) onto the window from Finder anywhere —
        // the sidebar and the detail pane both accept drops, not just the
        // empty state, so this works whether or not a document is selected.
        .dropDestination(for: URL.self) { urls, _ in
            let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfURLs.isEmpty else { return false }
            appState.importDocuments(at: pdfURLs)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.05))
                    .allowsHitTesting(false)
                    .padding(4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Import a scanned PDF to begin")
                .font(.title3)
            Text("or drag a PDF here")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Import PDF…") { isImporterPresented = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Routes to the right stage view based on the selected document's status.
private struct DocumentDetailView: View {
    @ObservedObject var document: DocumentItem
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch document.status {
        case .imported, .analyzing:
            ProcessingProgressView(title: "Analyzing pages…", detail: nil, progress: nil)

        case .readyForCrop:
            CropReviewView(document: document)

        case .ocrRunning(let pageIndex, let totalPages):
            ProcessingProgressView(
                title: "Running OCR…",
                detail: "Page \(pageIndex + 1) of \(totalPages)",
                progress: totalPages > 0 ? Double(pageIndex + 1) / Double(totalPages) : nil
            )

        case .readyForReview:
            ReviewAndExportView(document: document)

        case .finalizing:
            ProcessingProgressView(title: "Writing output files…", detail: nil, progress: nil)

        case .done(let outputs):
            DocumentDoneView(document: document, outputs: outputs)

        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                Text(message)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Retry") { Task { await appState.analyze(document) } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CropReviewView: View {
    @ObservedObject var document: DocumentItem
    @EnvironmentObject private var appState: AppState
    @State private var selectedPageIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            if document.pages.indices.contains(selectedPageIndex) {
                CropOverlayView(
                    page: document.pages[selectedPageIndex],
                    cropBox: cropBoxBinding(for: selectedPageIndex)
                )
            }
            Divider()
            HStack {
                Picker("Page", selection: $selectedPageIndex) {
                    ForEach(document.pages) { page in
                        Text("Page \(page.pageIndex + 1)").tag(page.pageIndex)
                    }
                }
                .frame(width: 160)

                Button("Apply to All Pages") { applyCurrentCropToAllPages() }

                Spacer()

                Button("Start OCR") {
                    Task { await appState.runOCR(document) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private func cropBoxBinding(for pageIndex: Int) -> Binding<BoundingBox> {
        Binding(
            get: {
                document.pageOptions.first { $0.pageIndex == pageIndex }?.cropBox
                    ?? document.pages.first { $0.pageIndex == pageIndex }?.detectedCropBox
                    ?? BoundingBox(x: 0, y: 0, width: 0, height: 0)
            },
            set: { newValue in
                if let idx = document.pageOptions.firstIndex(where: { $0.pageIndex == pageIndex }) {
                    document.pageOptions[idx].cropBox = newValue
                }
            }
        )
    }

    private func applyCurrentCropToAllPages() {
        guard let currentBox = document.pageOptions.first(where: { $0.pageIndex == selectedPageIndex })?.cropBox else { return }
        for i in document.pageOptions.indices {
            document.pageOptions[i].cropBox = currentBox
        }
    }
}

private struct DocumentDoneView: View {
    @ObservedObject var document: DocumentItem
    let outputs: FinalizeOutputs

    @State private var zoteroStatus: ZoteroStatus = .idle

    private enum ZoteroStatus: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Done")
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                if let path = outputs.searchablePdf {
                    outputRow("Searchable PDF", path)
                }
                if let path = outputs.plainText {
                    outputRow("Plain text", path)
                }
                if let path = outputs.pdfA {
                    outputRow("PDF/A", path)
                }
            }

            if outputs.searchablePdf != nil {
                zoteroSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func outputRow(_ label: String, _ path: String) -> some View {
        HStack {
            Text(label + ":").bold()
            Text(path).lineLimit(1).truncationMode(.middle)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    @ViewBuilder
    private var zoteroSection: some View {
        VStack(spacing: 6) {
            switch zoteroStatus {
            case .idle, .sending:
                Button {
                    sendToZotero()
                } label: {
                    Label("Send to Zotero", systemImage: "books.vertical")
                }
                .disabled(zoteroStatus == .sending)
            case .sent:
                Label("Sent to Zotero", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .failed(let message):
                VStack(spacing: 4) {
                    Label("Zotero로 보내지 못했습니다", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button("다시 시도") { sendToZotero() }
                }
            }
        }
    }

    private func sendToZotero() {
        guard let pdfPath = outputs.searchablePdf else { return }
        zoteroStatus = .sending
        Task {
            do {
                try await ZoteroService.saveItem(
                    title: document.selectedTitle,
                    author: document.selectedAuthor,
                    year: document.selectedYear,
                    pdfURL: URL(fileURLWithPath: pdfPath)
                )
                await MainActor.run { zoteroStatus = .sent }
            } catch {
                await MainActor.run {
                    zoteroStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
}
