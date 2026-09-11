import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("OCR Languages") {
                Toggle("Ancient Greek (grc)", isOn: $appState.useGreek)
                Toggle("Latin (lat)", isOn: $appState.useLatin)
                Toggle("English (eng)", isOn: $appState.useEnglish)
            }

            Section("Rasterization") {
                Picker("DPI", selection: $appState.dpi) {
                    Text("200 (faster)").tag(200)
                    Text("300 (recommended)").tag(300)
                    Text("400 (higher quality)").tag(400)
                }
            }

            Section("OCR Correction") {
                Toggle("Compute per-word confidence", isOn: $appState.computeConfidence)
                Text("Turning this off skips the confidence figures the OCR-correction view uses to flag words for review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}
