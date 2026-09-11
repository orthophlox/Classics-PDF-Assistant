"""OCR tests are gated on what's actually installed in this sandbox — never
assume. `tesseract-ocr`, `tesseract-ocr-eng`, `tesseract-ocr-grc`, and
`tesseract-ocr-lat` were confirmed installed via apt during development of
this backend (see docs/ARCHITECTURE.md); if a language isn't available here,
the corresponding test is skipped with an explicit reason rather than
silently passing, and README/backend docs note it needs manual verification
on the user's Mac (e.g. `brew install tesseract tesseract-lang`) before
relying on it in the shipped app.
"""

from __future__ import annotations

import shutil

import pytest

from pdf_backend import ocr
from tests.helpers import synthetic

try:
    import pytesseract

    _AVAILABLE_LANGS = set(pytesseract.get_languages(config=""))
except Exception:
    _AVAILABLE_LANGS = set()

_HAS_TESSERACT = shutil.which("tesseract") is not None


def _require(lang: str):
    if not _HAS_TESSERACT:
        pytest.skip("tesseract binary not installed in this sandbox")
    if lang not in _AVAILABLE_LANGS:
        pytest.skip(f"{lang}.traineddata not installed in this sandbox (available: {sorted(_AVAILABLE_LANGS)})")


def test_run_ocr_recognizes_english_text():
    _require("eng")
    page = synthetic.make_text_page(
        lines=["The quick brown fox jumps over the lazy dog."], font_size=36
    )
    arr = synthetic.to_rgb_ndarray(page)

    words = ocr.run_ocr(arr, languages=["eng"])
    recognized = " ".join(w.text for w in words).lower()

    assert "quick" in recognized
    assert "brown" in recognized
    assert all(w.confidence >= 0 for w in words)


def test_run_ocr_recognizes_greek_text():
    _require("grc")
    page = synthetic.make_text_page(lines=["λόγος καὶ ἀλήθεια"], font_size=40)
    arr = synthetic.to_rgb_ndarray(page)

    words = ocr.run_ocr(arr, languages=["grc"])
    recognized = "".join(w.text for w in words)

    assert len(words) >= 1
    # Ancient Greek OCR on a synthetic render is imperfect; just check some
    # Greek script made it through, not exact transcription.
    assert any("Ͱ" <= ch <= "Ͽ" or "ἀ" <= ch <= "῿" for ch in recognized)


def test_run_ocr_mixed_grc_lat_eng_language_string():
    _require("eng")
    if not ({"grc", "lat"} <= _AVAILABLE_LANGS):
        pytest.skip("grc/lat not both installed in this sandbox")
    page = synthetic.make_text_page(lines=["Homer Ilias λόγος 1920"], font_size=36)
    arr = synthetic.to_rgb_ndarray(page)

    # Should not raise with a multi-language string, regardless of per-word accuracy.
    words = ocr.run_ocr(arr, languages=["grc", "lat", "eng"])
    assert isinstance(words, list)


def test_mean_confidence_empty_list_is_negative_one():
    assert ocr.mean_confidence([]) == -1.0


def test_mean_confidence_averages_nonnegative_confidences():
    from pdf_backend.geometry import BoundingBox
    from pdf_backend.schemas import Word

    words = [
        Word(text="a", bbox=BoundingBox(0, 0, 1, 1), confidence=80.0),
        Word(text="b", bbox=BoundingBox(0, 0, 1, 1), confidence=90.0),
        Word(text="c", bbox=BoundingBox(0, 0, 1, 1), confidence=-1.0),
    ]
    assert ocr.mean_confidence(words) == 85.0
