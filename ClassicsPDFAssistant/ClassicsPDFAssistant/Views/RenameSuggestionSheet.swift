import SwiftUI

/// Bibliographic auto-rename: shows the backend's ranked title/author/year
/// candidates (from OCR of the title page) as editable, pre-filled fields,
/// with a live preview of the `{author} - {title} ({year}).pdf` filename.
/// Mirrors `render_filename`/`sanitize_filename` in `backend/pdf_backend/metadata.py`
/// via `MetadataFilename` for the live preview.
struct RenameSuggestionSheet: View {
    @ObservedObject var document: DocumentItem

    var body: some View {
        Form {
            Section("Suggested from title page") {
                candidatePicker("Author", candidates: document.metadataCandidates.author, selection: $document.selectedAuthor)
                candidatePicker("Title", candidates: document.metadataCandidates.title, selection: $document.selectedTitle)
                candidatePicker("Year", candidates: document.metadataCandidates.year, selection: $document.selectedYear)
            }

            Section("Filename Preview") {
                Text(document.suggestedOutputBasename + ".pdf")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func candidatePicker(_ label: String, candidates: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: selection)
                .textFieldStyle(.roundedBorder)
            if candidates.count > 1 {
                Picker("Other guesses", selection: selection) {
                    ForEach(candidates, id: \.self) { candidate in
                        Text(candidate).tag(candidate)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
