import Foundation

/// Watches a folder for newly added PDFs using a DispatchSource
/// file-system-object event (kqueue-based — no polling loop, no extra
/// framework). Used by AppState's watched-folder auto-processing feature:
/// drop a scanner's output folder in, and every new PDF gets the same
/// unattended analyze->ocr->finalize treatment as batch mode.
///
/// A newly-appeared file might still be mid-write (a scanner or Finder
/// copy in progress) — reporting it immediately risks handing the backend
/// a truncated PDF. Each candidate is checked for a stable file size after
/// a short delay before being reported; if it's still growing, the next
/// filesystem event will pick it up again.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var knownFiles: Set<String> = []
    private var scheduledForStabilityCheck: Set<String> = []
    private var folderURL: URL?
    private var onNewPDF: ((URL) -> Void)?

    private static let stabilityCheckDelay: TimeInterval = 2.0

    var isWatching: Bool { source != nil }

    /// - Parameters:
    ///   - folder: directory to watch (non-recursive — only files directly inside it).
    ///   - alreadySeen: file paths to treat as already processed (persisted across launches).
    ///   - onNewPDF: called on an arbitrary background queue once a new PDF's size has stabilized.
    func start(folder: URL, alreadySeen: Set<String>, onNewPDF: @escaping (URL) -> Void) {
        stop()
        folderURL = folder
        self.onNewPDF = onNewPDF
        knownFiles = alreadySeen

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.scanForNewFiles()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source

        // Catch anything already sitting in the folder when watching starts.
        scanForNewFiles()
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
        knownFiles.removeAll()
        scheduledForStabilityCheck.removeAll()
    }

    private func scanForNewFiles() {
        guard let folderURL else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }

        for url in entries where url.pathExtension.lowercased() == "pdf" {
            let path = url.path
            guard !knownFiles.contains(path), !scheduledForStabilityCheck.contains(path) else { continue }
            scheduledForStabilityCheck.insert(path)
            let sizeAtDiscovery = Self.fileSize(of: url)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.stabilityCheckDelay) { [weak self] in
                self?.confirmStable(url, sizeAtDiscovery: sizeAtDiscovery)
            }
        }
    }

    private func confirmStable(_ url: URL, sizeAtDiscovery: Int) {
        scheduledForStabilityCheck.remove(url.path)
        let currentSize = Self.fileSize(of: url)
        guard currentSize > 0, currentSize == sizeAtDiscovery else {
            // Still growing (or vanished) — the next filesystem event will
            // re-discover it and retry the stability check.
            return
        }
        guard !knownFiles.contains(url.path) else { return }
        knownFiles.insert(url.path)
        onNewPDF?(url)
    }

    private static func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
    }
}
