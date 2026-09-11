# pdf_backend

Deskew, OCR (grc+lat+eng), text-region crop, bibliographic metadata, and
export engine for Classics PDF Assistant. Talks to the SwiftUI app as a
subprocess over JSON — see `../docs/JSON_PROTOCOL.md` for the exact contract
and `../docs/ARCHITECTURE.md` for the design rationale.

## Setup

```bash
python3 -m venv ../.venv && source ../.venv/bin/activate
pip install -r requirements.txt
pip install -e ".[dev]"
```

Tesseract itself (the `tesseract` binary + language data) is a system
dependency, not a pip package. On Debian/Ubuntu:

```bash
apt-get install tesseract-ocr tesseract-ocr-eng tesseract-ocr-grc tesseract-ocr-lat tesseract-ocr-osd
```

On macOS (for local development outside the packaged app):

```bash
brew install tesseract tesseract-lang
```

## Tests

```bash
pytest
```

Deskew, crop, metadata, text-layer, and export tests are pure OpenCV/
PyMuPDF/regex logic against synthetically generated images and require no
Tesseract at all. OCR and pipeline integration tests are skipped (with an
explicit reason) if `tesseract` or a required language's `.traineddata`
isn't installed — never silently marked as passing.

## Manual testing without hand-writing JSON

```bash
python -m pdf_backend.cli process \
  --input /path/to/scan.pdf \
  --output /path/to/out.pdf \
  --lang grc+lat+eng \
  --plain-text --pdf-a
```

## Packaging for the macOS app

See `packaging/build_backend.sh` (macOS + Homebrew only — vendors a
Tesseract binary and its dylibs via `otool`/`install_name_tool`, freezes
this package with PyInstaller). Not runnable outside macOS; see
`docs/ARCHITECTURE.md` for what's built/tested where.
