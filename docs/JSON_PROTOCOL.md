# Backend JSON Protocol

The Swift app talks to the Python backend (`pdf_backend`) as a subprocess. Each
invocation reads one JSON request object from stdin and writes one JSON response
object to stdout. Long-running commands (`ocr`, `finalize`, `batch`) also write
newline-delimited JSON progress events to stderr, one per line, while running.

Invocation (both in dev and once frozen by PyInstaller):

```
python -m pdf_backend.cli <command> --request -
```

`<command>` is one of `analyze`, `ocr`, `finalize`, `batch`, matching the top-level
`command` field of the request body (the CLI also accepts convenience flags for
manual testing — see `cli.py --help`).

All coordinates are in **pixel space** at the DPI the page was rasterized at
(`dpi` field), origin top-left, unless noted otherwise.

## Shared types

```jsonc
// BoundingBox
{ "x": 10, "y": 12, "width": 500, "height": 700 }

// Word (produced by `ocr`, consumed/echoed by `finalize`)
{
  "text": "λόγος",
  "bbox": { "x": 100, "y": 200, "width": 60, "height": 22 },
  "confidence": 91.4     // 0-100, tesseract's per-word confidence; -1 if unknown
}

// PageOptions (per-page overrides sent into `ocr`/`finalize`)
{
  "page_index": 0,
  "crop_box": { "x": 10, "y": 12, "width": 500, "height": 700 },  // omit to use auto-detected
  "deskew_angle_deg": -1.3,                                        // omit to use auto-detected
  "words": [ /* Word[], only for finalize — corrected text, same bbox as returned by ocr */ ]
}

// ProgressEvent (stderr, NDJSON, one line per event)
{ "event": "page_progress", "document": "input.pdf", "page_index": 3, "total_pages": 40, "stage": "ocr" }
{ "event": "document_progress", "document": "input.pdf", "index": 1, "total_documents": 5 }  // batch only
```

## 1. `analyze`

Fast, no OCR. Rasterizes each page, runs deskew angle detection and text-region
crop detection. Used immediately after import so the UI can show a before/after
preview and let the user adjust crop boxes before committing to the slow OCR step.

Crop detection classifies the page into named regions — `main_text`, and,
for critical editions, `apparatus` (critical apparatus below the main text),
`margin_left`/`margin_right` (marginal line numbers), and `other` (anything
left over, e.g. a running header) — so the apparatus and margin numbers can
be excluded from OCR rather than swept into one crop box. `detected_crop_box`
is always the `main_text` region's box (unchanged shape from before this
existed, so it's still what `ocr`/`finalize` use by default); `detected_regions`
carries the full classification for the crop-review UI to display, and lets
the user pick a different region as the crop (or adjust any of them) before
committing to OCR. A plain page with no apparatus/margin content yields a
single `main_text` region equal to `detected_crop_box`. See
docs/ARCHITECTURE.md "Multi-region detection (critical editions)".

**Request**
```jsonc
{
  "command": "analyze",
  "input_pdf": "/path/in.pdf",
  "work_dir": "/tmp/classics-pdf/doc123",   // preview PNGs written here
  "options": { "dpi": 300, "deskew": true, "auto_crop": true, "crop_padding_pt": 12 }
}
```

**Response**
```jsonc
{
  "status": "ok",
  "error": null,
  "pages": [
    {
      "page_index": 0,
      "preview_image": "/tmp/classics-pdf/doc123/page-0.png",
      "skew_angle_deg": -1.3,
      "detected_crop_box": { "x": 10, "y": 12, "width": 500, "height": 700 },
      "detected_regions": [
        { "region_type": "main_text", "bbox": { "x": 10, "y": 12, "width": 500, "height": 700 } },
        { "region_type": "apparatus", "bbox": { "x": 10, "y": 730, "width": 500, "height": 120 } },
        { "region_type": "margin_left", "bbox": { "x": 0, "y": 12, "width": 8, "height": 700 } }
      ],
      "image_width": 2550,
      "image_height": 3300
    }
  ]
}
```

## 2. `ocr`

Given confirmed per-page crop box + deskew angle (auto-detected values, or
user overrides from the crop-review step), rasterizes+deskews+crops each page
and runs `pytesseract.image_to_data` once per page. This is the slow step;
per-page progress streams on stderr.

Also runs bibliographic-metadata heuristics (`metadata.py`) against the first
1-2 pages' words and returns ranked candidates for the rename-suggestion sheet.

**Request**
```jsonc
{
  "command": "ocr",
  "input_pdf": "/path/in.pdf",
  "work_dir": "/tmp/classics-pdf/doc123",
  "languages": ["grc", "lat", "eng"],
  "options": { "dpi": 300 },
  "pages": [ /* PageOptions[], from analyze (or user-adjusted) */ ]
}
```

**Response**
```jsonc
{
  "status": "ok",
  "error": null,
  "pages": [
    {
      "page_index": 0,
      "words": [ /* Word[] */ ],
      "mean_confidence": 87.2
    }
  ],
  "metadata_candidates": {
    "title": ["ΙΛΙΑΣ", "Ilias"],
    "author": ["Homer", "Homerus"],
    "year": ["1920", "1902"]
  }
}
```

## 3. `finalize`

Given the (possibly user-corrected) word lists and export options, builds the
invisible OCR text layer and writes output files. No OCR re-run — cheap and local.
`options.bw` binarizes only the *output* page images (Otsu threshold, pure
black ink on white) — OCR already ran (in `ocr`) against the original
grayscale/color rasterization and is unaffected either way.

**Request**
```jsonc
{
  "command": "finalize",
  "input_pdf": "/path/in.pdf",
  "work_dir": "/tmp/classics-pdf/doc123",
  "output_basename": "Homer - Ilias (1920)",   // from rename-suggestion sheet, pre-sanitized on Swift side
  "output_dir": "/Users/me/Documents/Classics",
  "options": {
    "dpi": 300,
    "searchable_pdf": true,
    "plain_text": true,
    "pdf_a": false,
    "bw": false   // black & white (bi-level, Otsu threshold) output images instead of grayscale/color
  },
  "pages": [ /* PageOptions[], words[] now holds corrected text */ ]
}
```

**Response**
```jsonc
{
  "status": "ok",
  "error": null,
  "outputs": {
    "searchable_pdf": "/Users/me/Documents/Classics/Homer - Ilias (1920).pdf",
    "plain_text": "/Users/me/Documents/Classics/Homer - Ilias (1920).txt",
    "pdf_a": null
  }
}
```

## 4. `batch`

Runs `analyze` → `ocr` → `finalize` per document inside one subprocess
invocation, using only auto-detected crop/deskew values (no manual per-page
review — batch mode is for unattended folder processing). Streams
`document_progress` and `page_progress` NDJSON events on stderr; one summary
JSON on stdout. Each successful document's result carries `mean_confidence`
— the average of its pages' OCR confidence — since batch mode has no
interactive review step to surface low-confidence pages any other way; a
caller (the watched-folder feature, in particular) can flag documents below
some threshold for the user to look at manually instead of trusting them
blindly.

**Request**
```jsonc
{
  "command": "batch",
  "documents": [
    { "input_pdf": "/path/a.pdf", "output_dir": "/path/out", "auto_rename": true },
    { "input_pdf": "/path/b.pdf", "output_dir": "/path/out", "auto_rename": true }
  ],
  "languages": ["grc", "lat", "eng"],
  "options": { "dpi": 300, "searchable_pdf": true, "plain_text": true, "pdf_a": false, "bw": false }
}
```

**Response**
```jsonc
{
  "status": "ok",
  "error": null,
  "documents": [
    { "input_pdf": "/path/a.pdf", "status": "ok", "outputs": { "searchable_pdf": "...", "plain_text": "...", "pdf_a": null }, "mean_confidence": 91.4 },
    { "input_pdf": "/path/b.pdf", "status": "error", "error": "..." }
  ]
}
```

`auto_rename: true` runs the same metadata heuristics as `ocr` and applies the
`{author} - {title} ({year})` template directly (sanitized), falling back to
the original filename when no candidates are found — batch mode has no UI to
confirm suggestions.

## Error shape

Any command can fail at the top level:
```jsonc
{ "status": "error", "error": "input_pdf not found: /path/in.pdf" }
```
Non-zero process exit code always accompanies a `status: "error"` response
(or, for a crash the CLI couldn't catch, no valid JSON on stdout at all — the
Swift side treats "non-zero exit + unparseable stdout" as the same error class).

## Design notes

- `analyze` and `ocr` are separated because OCR is 10-100x slower than
  deskew/crop detection and the user should be able to review/adjust crop
  boxes before paying that cost.
- `ocr` and `finalize` are separated because building the final PDF from
  already-computed word data is cheap; this lets the OCR-correction UI
  (feature 4) edit `words[].text` and re-`finalize` without re-running
  Tesseract.
- A single `image_to_data` call per page in `ocr` serves three features at
  once: the invisible text layer (`finalize`), the correction view
  (confidence-highlighted words), and plain-text export (words joined in
  reading order) — see `docs/ARCHITECTURE.md`.
