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

            WatchedFolderSection()
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}

/// Watched-folder auto-processing: drop a scanner's output folder in, and
/// every new PDF gets the same unattended treatment as batch mode (see
/// AppState.processWatchedFile / FolderWatcher). No manual crop/OCR review —
/// this is for hands-off pipelines, so the activity log below is the only
/// feedback, with mean OCR confidence flagged per file so a bad scan doesn't
/// silently slip through.
private struct WatchedFolderSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var isWatchFolderPickerPresented = false
    @State private var isOutputFolderPickerPresented = false

    var body: some View {
        Section("Watched Folder") {
            Toggle("Watch a folder for new PDFs", isOn: watchingBinding)
                .disabled(appState.watchedFolderURL == nil)

            LabeledContent("Watch") {
                folderRow(path: appState.watchedFolderURL?.path, action: { isWatchFolderPickerPresented = true })
            }
            LabeledContent("Save Output To") {
                folderRow(path: appState.watchedFolderOutputURL.path, action: { isOutputFolderPickerPresented = true })
            }

            if appState.watchedFolderURL == nil {
                Text("Choose a folder to watch — new PDFs dropped in it are processed automatically (auto-detected crop/deskew, no manual review, same as batch mode) and saved to the output folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appState.watchedFolderActivity.isEmpty {
                ActivityLog(items: appState.watchedFolderActivity)
            }
        }
        .fileImporter(isPresented: $isWatchFolderPickerPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let wasWatching = appState.isWatchingFolder
                appState.watchedFolderURL = url
                if wasWatching { appState.startWatchingFolder() }
            }
        }
        .fileImporter(isPresented: $isOutputFolderPickerPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                appState.watchedFolderOutputURL = url
            }
        }
    }

    private var watchingBinding: Binding<Bool> {
        Binding(
            get: { appState.isWatchingFolder },
            set: { newValue in
                if newValue {
                    appState.startWatchingFolder()
                } else {
                    appState.stopWatchingFolder()
                }
            }
        )
    }

    private func folderRow(path: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Text(path ?? "Not set")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(path == nil ? .secondary : .primary)
            Button("Choose…", action: action)
        }
    }
}

private struct ActivityLog: View {
    let items: [WatchedFolderActivityItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Activity")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(items.prefix(5)) { item in
                HStack(spacing: 6) {
                    statusIcon(item.status)
                    Text(item.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if case .done(let confidence) = item.status, let confidence {
                        Text("\(Int(confidence))%")
                            .font(.caption2)
                            .foregroundStyle(confidence < Word.lowConfidenceThreshold ? .red : .secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: WatchedFolderActivityItem.Status) -> some View {
        switch status {
        case .processing:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).imageScale(.small)
        }
    }
}
