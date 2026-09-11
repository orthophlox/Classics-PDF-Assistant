"""Plain-text export and lightweight PDF/A export.

PDF/A here is deliberately lightweight: pikepdf writes XMP metadata and an
sRGB ICC output intent onto the already-finalized PDF. This is
"PDF/A-leaning", not veraPDF-validated compliance — full compliance
typically means a Ghostscript pass, and bundling a second heavy native
binary (alongside Tesseract) into the macOS app was rejected as
disproportionate for what is a nice-to-have archival option, not a core
requirement. See docs/ARCHITECTURE.md.
"""

from __future__ import annotations

import os

import pikepdf

from .metadata import cluster_lines, line_text
from .schemas import Word

_CANDIDATE_ICC_PATHS = [
    os.path.join(os.path.dirname(__file__), "assets", "sRGB.icc"),
    "/usr/share/color/icc/sRGB.icc",
]


def _resolve_icc_path() -> str | None:
    for path in _CANDIDATE_ICC_PATHS:
        if os.path.isfile(path):
            return path
    return None


def words_to_text(pages: list[list[Word]]) -> str:
    """Join OCR words in reading order: line-clustered by y-overlap, then
    x-sorted within each line, pages separated by a form-feed.
    """
    page_texts = []
    for page_words in pages:
        lines = cluster_lines(page_words)
        page_texts.append("\n".join(line_text(line) for line in lines))
    return "\f".join(page_texts)


def write_plain_text(pages: list[list[Word]], output_path: str) -> str:
    text = words_to_text(pages)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(text)
    return output_path


def make_pdf_a_leaning(input_pdf_path: str, output_pdf_path: str, title: str = "") -> str:
    """Write a copy of input_pdf_path with PDF/A-style XMP metadata and an
    sRGB output intent. Best-effort: if no ICC profile is available at all
    (shouldn't happen once packaged — see backend/packaging/), the output
    still gets XMP metadata alone rather than failing outright.
    """
    icc_path = _resolve_icc_path()

    with pikepdf.open(input_pdf_path) as pdf:
        with pdf.open_metadata() as meta:
            meta["pdfaid:part"] = "2"
            meta["pdfaid:conformance"] = "B"
            if title:
                meta["dc:title"] = title

        if icc_path:
            with open(icc_path, "rb") as f:
                icc_bytes = f.read()
            output_intent_stream = pikepdf.Stream(pdf, icc_bytes)
            output_intent_stream["/N"] = 3
            output_intent_stream["/Alternate"] = pikepdf.Name("/DeviceRGB")
            output_intent = pikepdf.Dictionary(
                {
                    "/Type": pikepdf.Name("/OutputIntent"),
                    "/S": pikepdf.Name("/GTS_PDFA1"),
                    "/OutputConditionIdentifier": pikepdf.String("sRGB IEC61966-2.1"),
                    "/DestOutputProfile": output_intent_stream,
                }
            )
            pdf.Root.OutputIntents = pikepdf.Array([output_intent])

        pdf.save(output_pdf_path)

    return output_pdf_path
