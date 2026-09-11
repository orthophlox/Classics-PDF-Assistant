import Foundation

/// Locates the bundled `pdf_backend_cli` executable (see
/// backend/packaging/build_backend.sh, which places it in the app bundle's
/// Resources under a "PdfBackend" subdirectory via an Xcode Run Script
/// build phase) — or, in local development before that build phase has
/// ever run, falls back to invoking the repo's Python venv directly so the
/// app can be exercised against a live `backend/` checkout.
enum BackendLocator {
    static func bundledExecutable() -> URL? {
        Bundle.main.url(forResource: "pdf_backend_cli", withExtension: nil, subdirectory: "PdfBackend")
    }

    static func bundledTessdataDirectory() -> URL? {
        Bundle.main.url(forResource: "tessdata", withExtension: nil, subdirectory: "PdfBackend")
    }

    /// Dev-only fallback: `$CLASSICS_PDF_ASSISTANT_REPO_ROOT/.venv/bin/python3 -m pdf_backend.cli`.
    /// Set that environment variable (e.g. in an Xcode scheme) to point at a
    /// local checkout of this repository with `backend/README.md`'s venv
    /// already set up.
    static func devInvocation() -> (executable: URL, argumentsPrefix: [String])? {
        guard let repoRoot = ProcessInfo.processInfo.environment["CLASSICS_PDF_ASSISTANT_REPO_ROOT"] else {
            return nil
        }
        let venvPython = URL(fileURLWithPath: repoRoot)
            .appendingPathComponent(".venv/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: venvPython.path) else { return nil }
        return (venvPython, ["-m", "pdf_backend.cli"])
    }

    static func devTessdataDirectory() -> URL? {
        guard let repoRoot = ProcessInfo.processInfo.environment["CLASSICS_PDF_ASSISTANT_REPO_ROOT"] else {
            return nil
        }
        // In dev mode Tesseract resolves language data from the system
        // install (apt/brew), not TESSDATA_PREFIX, unless this is set —
        // left unset by default so `brew install tesseract tesseract-lang`'s
        // own tessdata is used.
        return URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("backend/packaging/tessdata")
    }
}
