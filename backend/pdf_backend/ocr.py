"""Word-level OCR via a single pytesseract.image_to_data call per page.

Deliberately not using pytesseract.image_to_pdf_or_hocr: that renders an
opaque, Tesseract-internal PDF text layer with no way to substitute a
corrected word afterward. image_to_data gives per-word text + bbox +
confidence once, and textlayer.py builds the actual PDF text layer from that
same data — so one Tesseract call serves the final PDF, the OCR-correction
view, and plain-text export.
"""

from __future__ import annotations

import numpy as np
import pytesseract
from pytesseract import Output

from .geometry import BoundingBox
from .schemas import Word


def run_ocr(image: np.ndarray, languages: list[str], psm: int = 3) -> list[Word]:
    """Run Tesseract on a single page image, returning non-empty words with
    their pixel-space bounding boxes and confidences (0-100, or -1 if
    Tesseract didn't report one for that token).
    """
    lang = "+".join(languages)
    data = pytesseract.image_to_data(
        image, lang=lang, config=f"--psm {psm}", output_type=Output.DICT
    )

    words: list[Word] = []
    for i, text in enumerate(data["text"]):
        if not text or not text.strip():
            continue
        try:
            conf = float(data["conf"][i])
        except (KeyError, ValueError, TypeError):
            conf = -1.0
        bbox = BoundingBox(
            x=int(data["left"][i]),
            y=int(data["top"][i]),
            width=int(data["width"][i]),
            height=int(data["height"][i]),
        )
        words.append(Word(text=text, bbox=bbox, confidence=conf))
    return words


def mean_confidence(words: list[Word]) -> float:
    confidences = [w.confidence for w in words if w.confidence >= 0]
    if not confidences:
        return -1.0
    return sum(confidences) / len(confidences)
