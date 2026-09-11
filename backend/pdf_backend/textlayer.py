"""Build a single-page PDF: the scanned page image as background, with an
invisible OCR text layer positioned per word (PDF text render mode 3), built
from data produced by ocr.py — so a user's correction to a word's text
(same bbox, edited text) flows straight through to the final searchable PDF
without re-running Tesseract.
"""

from __future__ import annotations

import io
import os

import numpy as np
import pymupdf
from PIL import Image

from .geometry import points_to_dpi_scale
from .schemas import Word

# DejaVu Sans covers Latin (incl. extended) and polytonic Greek, which the
# base-14 PDF fonts (Helvetica etc.) do not. Bundled into the packaged app
# alongside tessdata — see backend/packaging/. Falls back to Helvetica (with
# degraded text-layer fidelity for Greek) if not found, rather than failing.
_CANDIDATE_FONT_PATHS = [
    os.path.join(os.path.dirname(__file__), "assets", "DejaVuSans.ttf"),
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def _resolve_font_path() -> str | None:
    for path in _CANDIDATE_FONT_PATHS:
        if os.path.isfile(path):
            return path
    return None


_FONT_PATH = _resolve_font_path()
_MEASURE_FONT = pymupdf.Font(fontfile=_FONT_PATH) if _FONT_PATH else pymupdf.Font(fontname="helv")


def _image_to_png_bytes(image: np.ndarray) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(image).save(buf, format="PNG")
    return buf.getvalue()


def build_page_pdf(image: np.ndarray, words: list[Word], dpi: int) -> bytes:
    """Build a one-page PDF matching the image's pixel dimensions (at `dpi`),
    with `words` placed as an invisible, selectable text layer.
    """
    px_per_pt = points_to_dpi_scale(dpi)
    h_px, w_px = image.shape[:2]
    page_width_pt = w_px / px_per_pt
    page_height_pt = h_px / px_per_pt

    doc = pymupdf.open()
    page = doc.new_page(width=page_width_pt, height=page_height_pt)
    page.insert_image(pymupdf.Rect(0, 0, page_width_pt, page_height_pt), stream=_image_to_png_bytes(image))

    font_kwargs = {"fontfile": _FONT_PATH, "fontname": "OCRText"} if _FONT_PATH else {"fontname": "helv"}

    for word in words:
        text = word.text.strip()
        if not text:
            continue
        x_pt = word.bbox.x / px_per_pt
        y_top_pt = word.bbox.y / px_per_pt
        h_pt = word.bbox.height / px_per_pt
        w_pt = word.bbox.width / px_per_pt
        if h_pt <= 0 or w_pt <= 0:
            continue

        fontsize = max(h_pt * 0.9, 1.0)
        baseline_y = y_top_pt + h_pt * 0.88

        # Scale horizontally so the invisible run spans the detected word
        # width regardless of font-metric mismatch with the original glyphs —
        # keeps corrected/retyped words aligned with their scan position.
        text_width = _MEASURE_FONT.text_length(text, fontsize=fontsize)
        h_scale = min(max(w_pt / text_width, 0.1), 10.0) if text_width > 0 else 1.0

        try:
            page.insert_text(
                (x_pt, baseline_y),
                text,
                fontsize=fontsize,
                render_mode=3,  # invisible: neither fill nor stroke
                morph=(pymupdf.Point(x_pt, baseline_y), pymupdf.Matrix(h_scale, 1)),
                **font_kwargs,
            )
        except (RuntimeError, ValueError):
            # A glyph unsupported by the chosen font shouldn't take down the
            # whole page's text layer — skip just that word.
            continue

    pdf_bytes = doc.tobytes(deflate=True, garbage=3)
    doc.close()
    return pdf_bytes
