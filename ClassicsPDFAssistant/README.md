# ClassicsPDFAssistant (macOS app)

SwiftUI source for the native macOS app. Written and organized to match
`../docs/JSON_PROTOCOL.md` exactly, but **not compiled or run** in this
repository's Linux dev sandbox — it needs Xcode on macOS.

## First-time setup (on your Mac)

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
   (the `.xcodeproj` itself isn't checked in — a hand-written `.pbxproj`
   can't be validated without Xcode, so `project.yml` is the source of
   truth and XcodeGen generates a guaranteed-valid project from it).
2. From this directory: `xcodegen generate`
3. Open `ClassicsPDFAssistant.xcodeproj` in Xcode.

At this point the app will build and run against the **dev backend
fallback**: `BackendLocator` falls back to `$CLASSICS_PDF_ASSISTANT_REPO_ROOT/.venv/bin/python3
-m pdf_backend.cli` (already wired into the generated scheme's environment
variables) when no bundled `pdf_backend_cli` is found — so set up
`../backend`'s venv per `../backend/README.md` first, and language data
comes from your system Tesseract (`brew install tesseract tesseract-lang`).

## Building the real bundled backend

Before archiving a release build (or to test the actual packaged-app code
path), run `../backend/packaging/build_backend.sh` — it freezes
`pdf_backend` with PyInstaller and vendors a Tesseract binary + grc/lat/eng
tessdata. The Xcode project's build phase then embeds that output into the
app bundle's `Resources/PdfBackend`. See that script's comments and
`../docs/ARCHITECTURE.md` for what is and isn't verifiable outside macOS.

## Source layout

- `App/` — app entry point and `AppState` (the single source of truth for
  imported documents and their pipeline status).
- `Models/` — Codable structs mirroring `../docs/JSON_PROTOCOL.md`, plus
  app-local state (`DocumentItem`, `DocumentStatus`).
- `Backend/` — `BackendService` (the `Process`/JSON subprocess wrapper) and
  `BackendLocator` (bundled vs. dev-fallback executable resolution).
- `Services/` — `ZoteroService`, a standalone Swift-only (no Python backend
  involved) integration with a locally running Zotero desktop app; see its
  file header and `../docs/ARCHITECTURE.md` "Zotero handoff" before editing
  the request shapes, since it speaks an unofficial protocol.
- `Views/` — one view per pipeline stage, routed by `DocumentItem.status`
  in `ContentView`. See file-level doc comments for what each does.
