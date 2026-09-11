import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isImporterPresented = false

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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Import a scanned PDF to begin")
                .font(.title3)
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
            DocumentDoneView(outputs: outputs)

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
    let outputs: FinalizeOutputs

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
}
