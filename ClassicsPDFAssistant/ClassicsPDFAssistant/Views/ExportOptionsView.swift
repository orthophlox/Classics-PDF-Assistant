import SwiftUI

/// Export-format toggles: plain-text export, lightweight PDF/A, and a
/// black & white (bi-level) output-image option. The searchable PDF itself
/// is always produced — it's the core deliverable, not an optional extra.
struct ExportOptionsView: View {
    @Binding var options: FinalizeOptions
    @Binding var outputDirectory: URL
    @State private var isDirectoryPickerPresented = false

    var body: some View {
        Form {
            Section("Also export") {
                Toggle("Plain text (.txt)", isOn: $options.plainText)
                Toggle("PDF/A (lightweight, metadata + ICC only)", isOn: $options.pdfA)
            }

            Section("Page images") {
                Toggle("Black & white (bi-level)", isOn: $options.bw)
                Text("Converts scanned pages to pure black/white instead of grayscale — smaller files, same OCR accuracy (OCR already ran on the original scan).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Save to") {
                HStack {
                    Text(outputDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { isDirectoryPickerPresented = true }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isDirectoryPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                outputDirectory = url
            }
        }
    }
}
