"""textlayer.py needs no Tesseract at all — it only turns already-computed
Word data into a PDF, so these tests construct Word lists by hand.
"""

from __future__ import annotations

import pypdf

from pdf_backend import textlayer
from pdf_backend.geometry import BoundingBox
from pdf_backend.schemas import Word
from tests.helpers import synthetic


def _extract_text(pdf_bytes: bytes) -> str:
    reader = pypdf.PdfReader(__import__("io").BytesIO(pdf_bytes))
    return "\n".join(page.extract_text() or "" for page in reader.pages)


def test_build_page_pdf_dimensions_match_image_at_dpi():
    dpi = 300
    page = synthetic.make_text_page(width=900, height=1200)
    arr = synthetic.to_rgb_ndarray(page)

    pdf_bytes = textlayer.build_page_pdf(arr, words=[], dpi=dpi)

    reader = pypdf.PdfReader(__import__("io").BytesIO(pdf_bytes))
    assert len(reader.pages) == 1
    mb = reader.pages[0].mediabox
    expected_w_pt = 900 / (dpi / 72.0)
    expected_h_pt = 1200 / (dpi / 72.0)
    assert abs(float(mb.width) - expected_w_pt) < 1.0
    assert abs(float(mb.height) - expected_h_pt) < 1.0


def test_build_page_pdf_embeds_extractable_text():
    dpi = 300
    page = synthetic.make_text_page(width=900, height=1200)
    arr = synthetic.to_rgb_ndarray(page)

    words = [
        Word(text="Homerus", bbox=BoundingBox(x=100, y=200, width=180, height=40), confidence=95.0),
        Word(text="Ilias", bbox=BoundingBox(x=300, y=200, width=100, height=40), confidence=91.0),
    ]
    pdf_bytes = textlayer.build_page_pdf(arr, words=words, dpi=dpi)

    text = _extract_text(pdf_bytes)
    assert "Homerus" in text
    assert "Ilias" in text


def test_build_page_pdf_handles_empty_words_without_error():
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)
    pdf_bytes = textlayer.build_page_pdf(arr, words=[], dpi=300)
    assert pdf_bytes.startswith(b"%PDF")


def test_build_page_pdf_skips_blank_words_without_error():
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)
    words = [Word(text="   ", bbox=BoundingBox(0, 0, 10, 10), confidence=50.0)]
    pdf_bytes = textlayer.build_page_pdf(arr, words=words, dpi=300)
    assert pdf_bytes.startswith(b"%PDF")


def test_build_page_pdf_supports_greek_text():
    dpi = 300
    page = synthetic.make_text_page(width=900, height=1200)
    arr = synthetic.to_rgb_ndarray(page)

    words = [Word(text="λόγος", bbox=BoundingBox(x=100, y=200, width=140, height=44), confidence=88.0)]
    pdf_bytes = textlayer.build_page_pdf(arr, words=words, dpi=dpi)

    text = _extract_text(pdf_bytes)
    assert "λόγος" in text
