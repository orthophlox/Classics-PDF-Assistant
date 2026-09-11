"""pipeline.finalize()'s bw (black & white) option, kept separate from
test_pipeline.py so it can run without a tesseract dependency: finalize()
never calls OCR, and passing an explicit deskew_angle_deg avoids the
auto-detect deskew path's OSD (Tesseract) call too.
"""

from __future__ import annotations

import numpy as np
import pypdf

from pdf_backend import pdf_io, pipeline
from pdf_backend.schemas import FinalizeOptions, PageOptions
from tests.helpers import synthetic


def test_finalize_bw_option_produces_bi_level_embedded_image(tmp_path):
    dpi = 200
    page = synthetic.make_text_page(width=800, height=1000)
    pdf_path = tmp_path / "in.pdf"
    synthetic.images_to_pdf([page], dpi=dpi, output_path=str(pdf_path))

    page_options = [PageOptions(page_index=0, crop_box=None, deskew_angle_deg=0.0, words=[])]

    bw_options = FinalizeOptions(dpi=dpi, searchable_pdf=True, plain_text=False, pdf_a=False, bw=True)
    bw_outputs = pipeline.finalize(str(pdf_path), "bw_out", str(tmp_path / "bw"), bw_options, page_options)

    color_options = FinalizeOptions(dpi=dpi, searchable_pdf=True, plain_text=False, pdf_a=False, bw=False)
    color_outputs = pipeline.finalize(str(pdf_path), "color_out", str(tmp_path / "color"), color_options, page_options)

    # Re-rasterize at the same dpi the image was embedded at — rasterizing
    # at a different resolution (e.g. pymupdf's default get_pixmap() zoom)
    # would resample/interpolate the embedded bi-level image and manufacture
    # intermediate gray values that were never actually in the output file.
    bw_doc = pdf_io.open_pdf(bw_outputs["searchable_pdf"])
    bw_arr = pdf_io.rasterize_page(bw_doc, 0, dpi)
    unique_values = set(np.unique(bw_arr).tolist())
    assert unique_values <= {0, 255}, f"expected bi-level output, got {sorted(unique_values)}"
    bw_doc.close()

    # Bi-level PNG compresses far better than the grayscale/color original —
    # a coarse but meaningful signal that the toggle actually changed the
    # embedded image rather than being a no-op.
    bw_size = len(open(bw_outputs["searchable_pdf"], "rb").read())
    color_size = len(open(color_outputs["searchable_pdf"], "rb").read())
    assert bw_size < color_size

    # Text layer is unaffected by the bw toggle — both should still be valid PDFs.
    reader = pypdf.PdfReader(bw_outputs["searchable_pdf"])
    assert len(reader.pages) == 1


def test_finalize_without_bw_keeps_grayscale_shading(tmp_path):
    dpi = 200
    page = synthetic.make_text_page(width=800, height=1000)
    pdf_path = tmp_path / "in.pdf"
    synthetic.images_to_pdf([page], dpi=dpi, output_path=str(pdf_path))

    page_options = [PageOptions(page_index=0, crop_box=None, deskew_angle_deg=0.0, words=[])]
    options = FinalizeOptions(dpi=dpi, searchable_pdf=True, bw=False)
    outputs = pipeline.finalize(str(pdf_path), "out", str(tmp_path / "out"), options, page_options)

    doc = pdf_io.open_pdf(outputs["searchable_pdf"])
    arr = pdf_io.rasterize_page(doc, 0, dpi)
    # Anti-aliased text rendering should retain more than two intensity
    # levels when bw is off.
    assert len(np.unique(arr)) > 2
    doc.close()
