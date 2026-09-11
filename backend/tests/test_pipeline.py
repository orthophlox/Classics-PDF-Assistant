"""End-to-end integration test: a synthetic 2-page "scanned book" (rotated +
offset text, border noise) run through analyze -> ocr -> finalize. Gated on
tesseract-ocr-eng, which was confirmed installed in this sandbox (see
docs/ARCHITECTURE.md) — never assumed.
"""

from __future__ import annotations

import shutil

import pypdf
import pytest

from pdf_backend import pipeline
from pdf_backend.schemas import AnalyzeOptions, FinalizeOptions, PageOptions
from tests.helpers import synthetic

try:
    import pytesseract

    _HAS_ENG = "eng" in set(pytesseract.get_languages(config=""))
except Exception:
    _HAS_ENG = False

_HAS_TESSERACT = shutil.which("tesseract") is not None

pytestmark = pytest.mark.skipif(
    not (_HAS_TESSERACT and _HAS_ENG),
    reason="tesseract-ocr / tesseract-ocr-eng not installed in this sandbox",
)


@pytest.fixture()
def synthetic_book_pdf(tmp_path):
    dpi = 200
    page1 = synthetic.make_text_page(
        width=1000,
        height=1400,
        margin=150,
        lines=["The quick brown fox jumps over the lazy dog."],
        font_size=32,
    )
    page1 = synthetic.rotate_page(page1, 3.0)
    page1 = synthetic.add_border_noise(page1, thickness=10)

    page2 = synthetic.make_text_page(
        width=1000,
        height=1400,
        margin=150,
        lines=["Second page of classical text for testing purposes."],
        font_size=32,
    )

    pdf_path = tmp_path / "book.pdf"
    synthetic.images_to_pdf([page1, page2], dpi=dpi, output_path=str(pdf_path))
    return str(pdf_path), dpi


def test_full_pipeline_analyze_ocr_finalize(tmp_path, synthetic_book_pdf):
    input_pdf, dpi = synthetic_book_pdf
    work_dir = tmp_path / "work"
    output_dir = tmp_path / "out"

    analyze_options = AnalyzeOptions(dpi=dpi, deskew=True, auto_crop=True, crop_padding_pt=10)
    pages_analysis = pipeline.analyze(input_pdf, str(work_dir), analyze_options)

    assert len(pages_analysis) == 2
    for page in pages_analysis:
        # Crop should have found something narrower than the full raw page.
        assert page.detected_crop_box.width < page.image_width
        assert page.detected_crop_box.height < page.image_height

    page_options = [
        PageOptions(
            page_index=p.page_index,
            crop_box=p.detected_crop_box,
            deskew_angle_deg=p.skew_angle_deg,
        )
        for p in pages_analysis
    ]

    ocr_results, candidates = pipeline.ocr_document(
        input_pdf, languages=["eng"], dpi=dpi, pages=page_options
    )
    assert len(ocr_results) == 2
    words_by_index = {r.page_index: r.words for r in ocr_results}
    page0_text = " ".join(w.text for w in words_by_index[0]).lower()
    assert "quick" in page0_text or "brown" in page0_text or "fox" in page0_text

    for page_opt in page_options:
        page_opt.words = words_by_index[page_opt.page_index]

    finalize_options = FinalizeOptions(dpi=dpi, searchable_pdf=True, plain_text=True, pdf_a=False)
    outputs = pipeline.finalize(
        input_pdf, "Test Book", str(output_dir), finalize_options, page_options
    )

    assert outputs["searchable_pdf"] is not None
    reader = pypdf.PdfReader(outputs["searchable_pdf"])
    assert len(reader.pages) == 2
    extracted = "\n".join(p.extract_text() or "" for p in reader.pages).lower()
    assert "second" in extracted or "page" in extracted or "classical" in extracted

    assert outputs["plain_text"] is not None
    text_content = open(outputs["plain_text"], encoding="utf-8").read()
    assert text_content.strip() != ""


def test_run_command_dispatches_analyze(tmp_path, synthetic_book_pdf):
    input_pdf, dpi = synthetic_book_pdf
    request = {
        "command": "analyze",
        "input_pdf": input_pdf,
        "work_dir": str(tmp_path / "work2"),
        "options": {"dpi": dpi},
    }
    response = pipeline.run_command(request)
    assert response["status"] == "ok"
    assert len(response["pages"]) == 2


def test_run_command_reports_error_for_missing_file(tmp_path):
    request = {
        "command": "analyze",
        "input_pdf": str(tmp_path / "does_not_exist.pdf"),
        "work_dir": str(tmp_path / "work3"),
        "options": {},
    }
    response = pipeline.run_command(request)
    assert response["status"] == "error"
    assert "not found" in response["error"]


def test_run_command_unknown_command():
    response = pipeline.run_command({"command": "bogus"})
    assert response["status"] == "error"
    assert "unknown command" in response["error"]


def test_batch_process_handles_multiple_documents(tmp_path, synthetic_book_pdf):
    input_pdf, dpi = synthetic_book_pdf
    output_dir = tmp_path / "batch_out"
    options = FinalizeOptions(dpi=dpi, searchable_pdf=True, plain_text=True, pdf_a=False)

    documents = [
        {"input_pdf": input_pdf, "output_dir": str(output_dir), "auto_rename": False},
    ]
    results = pipeline.batch_process(documents, languages=["eng"], options=options)

    assert len(results) == 1
    assert results[0]["status"] == "ok"
    assert results[0]["outputs"]["searchable_pdf"] is not None
