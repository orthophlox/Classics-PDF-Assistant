# Architecture

Classics PDF Assistant is a macOS-native SwiftUI app for turning scanned PDFs of
classical texts (mixed Ancient Greek / Latin / English) into deskewed, cropped,
searchable PDFs — with an OCR-correction pass, plain-text/PDF-A export, batch
processing, and bibliography-based auto-rename.

## Two-process design

```
┌─────────────────────────────┐        JSON over stdin/stdout       ┌──────────────────────────────┐
│   SwiftUI app (native UI)   │ ───────────────────────────────────>│  Python backend (subprocess)  │
│                              │<─────────────────────────────────── │  pdf_backend, PyInstaller-    │
│  import, crop overlay,      │   NDJSON progress on stderr          │  frozen, bundles Tesseract +  │
│  OCR correction, rename     │                                      │  grc/lat/eng tessdata_best    │
│  sheet, export options      │                                      │  and OpenCV                   │
└─────────────────────────────┘                                      └──────────────────────────────┘
```

The UI is 100% native SwiftUI/AppKit. All PDF rasterization, image processing
(OpenCV), and OCR (pytesseract/Tesseract) live in the Python backend, invoked as
a subprocess per command — see `docs/JSON_PROTOCOL.md` for the exact request/
response shapes of the four commands (`analyze`, `ocr`, `finalize`, `batch`).

Why a subprocess instead of PythonKit/embedding: it keeps the two runtimes fully
decoupled (the Python side can be built, frozen, and tested independently — which
is what this repository's `backend/` is, in this Linux dev sandbox, without Xcode
at all), and a crash in OpenCV/Tesseract can't take down the SwiftUI process.

## Why one OCR call per page

Tesseract can render a searchable PDF directly
(`pytesseract.image_to_pdf_or_hocr(..., extension="pdf")`), but that render is
opaque — there's no way to substitute a corrected word afterward. Instead the
backend always calls `image_to_data(output_type=Output.DICT)` once per page,
which returns per-word text + bounding box + confidence, and:

1. **`finalize`** builds the invisible PDF text layer itself
   (`textlayer.py`, via PyMuPDF `page.insert_text(..., render_mode=3)`) from
   this word list — using corrected text where the OCR-correction view edited it.
2. **`OCRCorrectionView`** (Swift) shows the same words, highlighting anything
   below a confidence threshold, so a classicist proofing Ancient Greek OCR
   (which has a meaningfully higher error rate than Latin-script OCR) can fix
   it before the PDF is finalized.
3. **Plain-text export** (`export.py`) joins the same words in reading order
   (line-clustered by y-overlap, then x-sorted).

One Tesseract pass per page now serves three features instead of needing a
second, separate `image_to_pdf_or_hocr` call.

## Pipeline stages and why they're split

`analyze` (fast: rasterize + deskew-detect + crop-detect) is separate from `ocr`
(slow: Tesseract) so the user can review/adjust the auto-detected crop box
*before* paying OCR cost. `ocr` is separate from `finalize` (cheap: text-layer
+ file writing) so correcting OCR text doesn't require re-running Tesseract.
`batch` runs all three stages back-to-back per document inside one subprocess
invocation, using only auto-detected values (no manual review step), to avoid
per-document Python/OpenCV/Tesseract startup cost when processing a folder.

## Deskew

Two-pass: `pytesseract.image_to_osd()` first catches gross 90/180/270° page
rotations (a Hough/minAreaRect detector alone only handles small tilts and
would misread a sideways-scanned page as "no skew"); then Otsu binarize →
horizontal dilate → contour filtering → `cv2.minAreaRect` over the surviving
ink mass gives the fine sub-degree angle, applied via `cv2.warpAffine` with an
expanded canvas so corners aren't clipped.

## Crop (text-region detection)

Pure function (`crop.py`), independent of deskew and OCR, unit-tested against
synthetic images: Otsu threshold → morphological open (remove speckle) →
close (merge text lines/paragraphs into one mass, while still excluding thin
scanner-bed border artifacts) → contour filtering (drop border-touching
noise) → union bounding box + configurable padding.

## Bibliographic auto-rename

`metadata.py` runs heuristics over the first page(s)' OCR words: the
line-cluster with the largest median glyph height is the title candidate;
lines matching an author-pattern (`by`, `tr\.`, a capitalized name run) or the
next-largest block are author candidates; a `\b(1[4-9]\d{2}|20\d{2})\b` regex
over all first-page text yields year candidates. These are always returned as
ranked lists, never a single forced answer — the Swift `RenameSuggestionSheet`
pre-fills them but the user can edit before the `{author} - {title} ({year})`
template is applied and sanitized for the filesystem. In `batch` mode (no UI),
the top candidate of each is applied directly, falling back to the original
filename when no candidates were found.

## PDF/A export

Deliberately lightweight: `pikepdf` writes XMP metadata and an sRGB ICC output
intent onto the finalized PDF. This is "PDF/A-leaning" but not veraPDF-validated
compliance — a full Ghostscript-based conversion was considered and rejected
for this app because it requires bundling a second heavy native binary
alongside Tesseract, roughly doubling native-dependency packaging complexity
for a feature that's a nice-to-have, not a core requirement.

## What's built vs. designed-only in this repository

- `backend/` — implemented and tested in this repo's Linux dev sandbox
  (no macOS/Xcode available here). Deskew, crop, metadata, and export logic
  is tested against synthetic images with no Tesseract dependency; OCR tests
  are gated on the actual installed language data (verified, not assumed —
  see `backend/tests/test_ocr.py`).
- `ClassicsPDFAssistant/` — full SwiftUI source tree, written to match
  `docs/JSON_PROTOCOL.md` exactly, but not compiled/run here. Requires Xcode
  on macOS; see `ClassicsPDFAssistant/README.md` for `xcodegen generate` setup.
- `backend/packaging/` — PyInstaller spec and build scripts are written and
  documented, but bundling an actual Tesseract binary (resolving dylib
  dependencies via `otool`/`install_name_tool`) can only be done and verified
  on a real Mac build machine, not in this sandbox.
