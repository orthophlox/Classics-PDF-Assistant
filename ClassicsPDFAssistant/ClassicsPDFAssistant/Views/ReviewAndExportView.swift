import SwiftUI

/// The `.readyForReview` stage: proof/correct OCR output, confirm the
/// bibliographic rename suggestion, pick export options, then finalize.
/// Composes OCRCorrectionView + RenameSuggestionSheet + ExportOptionsView —
/// kept as three tabs rather than one long scroll, since each is a
/// substantial editing surface on its own.
struct ReviewAndExportView: View {
    @ObservedObject var document: DocumentItem
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = Tab.correction
    @State private var outputDirectory: URL

    private enum Tab: Hashable { case correction, rename, export }

    init(document: DocumentItem) {
        self.document = document
        _outputDirectory = State(initialValue: document.workDir)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Correct OCR").tag(Tab.correction)
                Text("Rename").tag(Tab.rename)
                Text("Export").tag(Tab.export)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Group {
                switch selectedTab {
                case .correction:
                    OCRCorrectionView(document: document)
                case .rename:
                    RenameSuggestionSheet(document: document)
                case .export:
                    ExportOptionsView(options: $document.exportOptions, outputDirectory: $outputDirectory)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                Spacer()
                Button("Finalize") {
                    Task {
                        await appState.finalizeDocument(document, outputDirectory: outputDirectoryOrDefault)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .onAppear {
            if outputDirectory == document.workDir {
                outputDirectory = appState.defaultOutputDirectory
            }
        }
    }

    private var outputDirectoryOrDefault: URL {
        outputDirectory
    }
}
