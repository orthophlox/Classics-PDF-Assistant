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

For a one-command build all the way to a distributable `.dmg` (this step,
`xcodegen generate`, and the `xcodebuild`/`hdiutil` packaging), see
`../scripts/build_dmg.sh` and the root `README.md`'s "맥에서 dmg로 바로
실행할 수 있나요?" section. No entitlement is set here for App Sandbox — see
`ClassicsPDFAssistant/Resources/ClassicsPDFAssistant.entitlements`'s comment
for why, if you're considering Mac App Store distribution later.

## Source layout

- `App/` — app entry point (which also wires up Sparkle's
  `SPUStandardUpdaterController` — see `../docs/ARCHITECTURE.md` "Auto-update
  (Sparkle)" and the root README's "자동 업데이트 설정하기" before it'll
  actually find updates), `CheckForUpdatesView` (the Sparkle menu-item
  recipe), `AppState` (the single source of truth for imported documents,
  their pipeline status, and the watched-folder feature's settings/activity
  log), and `UninstallFlow` (the App-menu "Uninstall…" command; see
  `../scripts/Uninstall.command` for the standalone script bundled in the
  `.dmg` that also removes the app itself).
- `Models/` — Codable structs mirroring `../docs/JSON_PROTOCOL.md`, plus
  app-local state (`DocumentItem`, `DocumentStatus`, `WatchedFolderActivityItem`).
- `Backend/` — `BackendService` (the `Process`/JSON subprocess wrapper) and
  `BackendLocator` (bundled vs. dev-fallback executable resolution).
- `Services/` — `ZoteroService`, a standalone Swift-only (no Python backend
  involved) integration with a locally running Zotero desktop app; see its
  file header and `../docs/ARCHITECTURE.md` "Zotero handoff" before editing
  the request shapes, since it speaks an unofficial protocol. Also
  `FolderWatcher`, the `DispatchSource`-based watched-folder implementation
  (see "Watched-folder auto-processing" in `../docs/ARCHITECTURE.md`).
- `Views/` — one view per pipeline stage, routed by `DocumentItem.status`
  in `ContentView` (which also handles drag-and-drop import). See
  file-level doc comments for what each does.
