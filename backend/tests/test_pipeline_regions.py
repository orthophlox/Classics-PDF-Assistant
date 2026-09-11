"""pipeline.analyze()'s multi-region wiring, kept separate from
test_pipeline.py so it can run without a tesseract dependency at all
(deskew=False skips the OSD coarse pass, which is the only place analyze()
touches Tesseract).
"""

from __future__ import annotations

from pdf_backend import pipeline
from pdf_backend.schemas import AnalyzeOptions
from tests.helpers import synthetic


def test_analyze_surfaces_detected_regions_for_critical_edition_layout(tmp_path):
    page = synthetic.make_critical_edition_page()
    pdf_path = tmp_path / "critical_edition.pdf"
    synthetic.images_to_pdf([page], dpi=200, output_path=str(pdf_path))

    options = AnalyzeOptions(dpi=200, deskew=False, auto_crop=True, crop_padding_pt=6)
    pages = pipeline.analyze(str(pdf_path), str(tmp_path / "work"), options)

    assert len(pages) == 1
    region_types = {r.region_type for r in pages[0].detected_regions}
    assert "main_text" in region_types
    assert "apparatus" in region_types
    assert "margin_left" in region_types
    assert "margin_right" in region_types

    # detected_crop_box (what OCR actually uses) must be the main_text region.
    main_text_bbox = next(r.bbox for r in pages[0].detected_regions if r.region_type == "main_text")
    assert pages[0].detected_crop_box == main_text_bbox
    # ...and specifically not the apparatus region, which is wider/taller
    # in this synthetic layout but must never be picked as "the" crop box.
    apparatus_bbox = next(r.bbox for r in pages[0].detected_regions if r.region_type == "apparatus")
    assert pages[0].detected_crop_box != apparatus_bbox


def test_analyze_plain_page_yields_single_main_text_region(tmp_path):
    page = synthetic.make_text_page()
    pdf_path = tmp_path / "plain.pdf"
    synthetic.images_to_pdf([page], dpi=200, output_path=str(pdf_path))

    options = AnalyzeOptions(dpi=200, deskew=False, auto_crop=True)
    pages = pipeline.analyze(str(pdf_path), str(tmp_path / "work"), options)

    assert len(pages[0].detected_regions) == 1
    assert pages[0].detected_regions[0].region_type == "main_text"


def test_analyze_no_auto_crop_yields_no_regions(tmp_path):
    page = synthetic.make_text_page()
    pdf_path = tmp_path / "plain.pdf"
    synthetic.images_to_pdf([page], dpi=200, output_path=str(pdf_path))

    options = AnalyzeOptions(dpi=200, deskew=False, auto_crop=False)
    pages = pipeline.analyze(str(pdf_path), str(tmp_path / "work"), options)

    assert pages[0].detected_regions == []
