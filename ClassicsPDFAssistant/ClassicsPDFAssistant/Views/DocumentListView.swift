import SwiftUI

struct DocumentListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isImporterPresented: Bool
    @State private var isFolderImporterPresented = false

    var body: some View {
        List(selection: $appState.selectedDocumentID) {
            ForEach(appState.documents) { document in
                DocumentRow(document: document)
                    .tag(document.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            appState.removeDocument(document)
                        }
                    }
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import PDF", systemImage: "doc.badge.plus")
                }
                Button {
                    isFolderImporterPresented = true
                } label: {
                    Label("Import Folder (Batch)", systemImage: "folder.badge.plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                appState.importFolder(at: url)
            }
        }
    }
}

private struct DocumentRow: View {
    @ObservedObject var document: DocumentItem

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
            VStack(alignment: .leading) {
                Text(document.displayName)
                    .lineLimit(1)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusIcon
        }
        .padding(.vertical, 2)
    }

    private var statusDescription: String {
        switch document.status {
        case .imported: return "Imported"
        case .analyzing: return "Analyzing…"
        case .readyForCrop: return "Ready to review crop"
        case .ocrRunning(let pageIndex, let total): return "OCR \(pageIndex + 1)/\(total)"
        case .readyForReview: return "Ready to review OCR"
        case .finalizing: return "Finalizing…"
        case .done: return "Done"
        case .error: return "Error"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch document.status {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .analyzing, .ocrRunning, .finalizing:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }
}
