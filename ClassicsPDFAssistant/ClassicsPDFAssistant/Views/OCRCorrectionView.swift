import SwiftUI

/// Proofs OCR output against the scan: the deskewed/cropped page image on
/// top, and an editable word list below with low-confidence words
/// (Word.needsReview) highlighted first. Edits flow straight into
/// `document.pageOptions[pageIndex].words`, which `finalize` uses to build
/// the invisible text layer — no re-OCR needed.
struct OCRCorrectionView: View {
    @ObservedObject var document: DocumentItem
    @State private var selectedPageIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Page", selection: $selectedPageIndex) {
                ForEach(document.pages) { page in
                    Text("Page \(page.pageIndex + 1)\(reviewBadge(for: page.pageIndex))").tag(page.pageIndex)
                }
            }
            .padding([.horizontal, .top])

            if let page = document.pages.first(where: { $0.pageIndex == selectedPageIndex }) {
                PagePreviewView(
                    imagePath: page.previewImage,
                    imagePixelSize: CGSize(width: page.imageWidth, height: page.imageHeight)
                )
                .frame(maxHeight: 320)
                .padding()

                Divider()

                WordEditorList(pageIndex: selectedPageIndex, document: document)
            } else {
                Spacer()
            }
        }
    }

    private func reviewBadge(for pageIndex: Int) -> String {
        let count = wordsNeedingReview(pageIndex).count
        return count > 0 ? " (\(count))" : ""
    }

    private func wordsNeedingReview(_ pageIndex: Int) -> [Word] {
        document.pageOptions.first { $0.pageIndex == pageIndex }?.words.filter(\.needsReview) ?? []
    }
}

private struct WordEditorList: View {
    let pageIndex: Int
    @ObservedObject var document: DocumentItem

    var body: some View {
        List {
            if let idx = document.pageOptions.firstIndex(where: { $0.pageIndex == pageIndex }) {
                let words = document.pageOptions[idx].words
                let needsReview = words.indices.filter { words[$0].needsReview }
                let clean = words.indices.filter { !words[$0].needsReview }

                if !needsReview.isEmpty {
                    Section("Needs Review (\(needsReview.count))") {
                        ForEach(needsReview, id: \.self) { wordIndex in
                            WordEditorRow(word: wordBinding(pageOptionsIndex: idx, wordIndex: wordIndex))
                        }
                    }
                }
                Section("All Words") {
                    ForEach(clean, id: \.self) { wordIndex in
                        WordEditorRow(word: wordBinding(pageOptionsIndex: idx, wordIndex: wordIndex))
                    }
                }
            } else {
                Text("No OCR data for this page yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func wordBinding(pageOptionsIndex: Int, wordIndex: Int) -> Binding<Word> {
        Binding(
            get: { document.pageOptions[pageOptionsIndex].words[wordIndex] },
            set: { document.pageOptions[pageOptionsIndex].words[wordIndex] = $0 }
        )
    }
}

private struct WordEditorRow: View {
    @Binding var word: Word

    var body: some View {
        HStack {
            TextField("Word", text: $word.text)
                .textFieldStyle(.roundedBorder)
            if word.confidence >= 0 {
                Text("\(Int(word.confidence))%")
                    .font(.caption)
                    .foregroundStyle(word.needsReview ? .red : .secondary)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .listRowBackground(word.needsReview ? Color.red.opacity(0.08) : Color.clear)
    }
}
