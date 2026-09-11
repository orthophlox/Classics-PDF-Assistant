# Classics PDF Assistant

A macOS-native app for preparing scanned PDFs of classical texts (mixed
Ancient Greek / Latin / English) for research and archiving:

1. **Automatic deskew** — detects and corrects page tilt.
2. **OCR → searchable PDF** — Tesseract (pytesseract), grc+lat+eng mixed
   recognition, invisible text layer over the original scan.
3. **Text-region cropping** — auto-detects the text bounding box per page,
   manually adjustable.
4. **OCR correction view** — proofs recognized text against the scan,
   highlighting low-confidence words.
5. **Batch processing** — run the whole pipeline over a folder of PDFs.
6. **Plain-text export** alongside the searchable PDF.
7. **Lightweight PDF/A export** (metadata + ICC profile, no Ghostscript).
8. **Bibliographic auto-rename** — suggests `{author} - {title} ({year}).pdf`
   from OCR'd title-page text, editable before applying.

See `docs/ARCHITECTURE.md` for the system design and `docs/JSON_PROTOCOL.md`
for the exact contract between the SwiftUI app and the Python backend.

## Repository layout

- `backend/` — Python engine (`pdf_backend`): deskew, crop, OCR, text-layer
  construction, metadata heuristics, export. Runs and is tested independently
  of the macOS app; see `backend/README.md`.
- `ClassicsPDFAssistant/` — SwiftUI app source. Requires Xcode on macOS to
  build; see `ClassicsPDFAssistant/README.md`.

## Development

```bash
cd backend
python3 -m venv ../.venv && source ../.venv/bin/activate
pip install -r requirements.txt
pip install -e ".[dev]"
pytest
```
