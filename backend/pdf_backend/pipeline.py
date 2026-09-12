"""Orchestrates the four JSON-protocol commands (analyze/ocr/finalize/batch)
over the lower-level modules. See docs/JSON_PROTOCOL.md for the wire shapes
this maps to/from, and docs/ARCHITECTURE.md for why the pipeline is split
this way.

Invariant: `dpi` must be the same value across a document's analyze -> ocr ->
finalize calls, since crop boxes and deskew results are pixel-space at that
DPI and get reinterpreted by each later stage.
"""

from __future__ import annotations

import io
import os
import shutil
import tempfile
from typing import Callable, Optional

import pypdf

from . import crop, deskew, export, metadata, ocr, pdf_io, textlayer
from .geometry import BoundingBox, points_to_dpi_scale
from .schemas import (
    AnalyzeOptions,
    FinalizeOptions,
    MetadataCandidates,
    PageAnalysis,
    PageOCRResult,
    PageOptions,
    error_response,
    ok_response,
)

ProgressCallback = Callable[[dict], None]


def _require_input_pdf(input_pdf: str) -> None:
    if not os.path.isfile(input_pdf):
        raise FileNotFoundError(f"input_pdf not found: {input_pdf}")


def analyze(
    input_pdf: str,
    work_dir: str,
    options: AnalyzeOptions,
    on_progress: Optional[ProgressCallback] = None,
) -> list[PageAnalysis]:
    _require_input_pdf(input_pdf)
    os.makedirs(work_dir, exist_ok=True)

    doc = pdf_io.open_pdf(input_pdf)
    total = pdf_io.page_count(doc)
    results: list[PageAnalysis] = []

    try:
        for i in range(total):
            image = pdf_io.rasterize_page(doc, i, options.dpi)

            skew_angle = 0.0
            working = image
            if options.deskew:
                working, skew_angle = deskew.deskew(image)

            h, w = working.shape[:2]
            if options.auto_crop:
                padding_px = int(round(options.crop_padding_pt * points_to_dpi_scale(options.dpi)))
                regions = crop.detect_regions(working, padding=padding_px)
                # The main_text region is what OCR actually uses by default
                # (detected_crop_box, unchanged shape from before this
                # feature existed); apparatus/margin regions ride along in
                # detected_regions purely for the UI to display and let the
                # user pick a different region as the crop, or adjust it —
                # see docs/ARCHITECTURE.md "Multi-region detection".
                detected_box = next(r.bbox for r in regions if r.region_type == "main_text")
            else:
                regions = []
                detected_box = BoundingBox(x=0, y=0, width=w, height=h)

            preview_path = os.path.join(work_dir, f"page-{i}.png")
            pdf_io.save_png(working, preview_path)

            results.append(
                PageAnalysis(
                    page_index=i,
                    preview_image=preview_path,
                    skew_angle_deg=skew_angle,
                    detected_crop_box=detected_box,
                    image_width=w,
                    image_height=h,
                    detected_regions=regions,
                )
            )
            if on_progress:
                on_progress(
                    {
                        "event": "page_progress",
                        "document": input_pdf,
                        "page_index": i,
                        "total_pages": total,
                        "stage": "analyze",
                    }
                )
    finally:
        doc.close()

    return results


def _prepare_page_image(doc, page_opt: PageOptions, dpi: int):
    image = pdf_io.rasterize_page(doc, page_opt.page_index, dpi)
    if page_opt.deskew_angle_deg is not None:
        image = deskew.apply_known_skew(image, page_opt.deskew_angle_deg)
    else:
        image, _ = deskew.deskew(image)
    if page_opt.crop_box is not None:
        b = page_opt.crop_box
        image = pdf_io.crop_np(image, b.x, b.y, b.width, b.height)
    return image


def ocr_document(
    input_pdf: str,
    languages: list[str],
    dpi: int,
    pages: list[PageOptions],
    on_progress: Optional[ProgressCallback] = None,
) -> tuple[list[PageOCRResult], MetadataCandidates]:
    _require_input_pdf(input_pdf)
    doc = pdf_io.open_pdf(input_pdf)
    total = len(pages)
    results: list[PageOCRResult] = []

    try:
        sorted_pages = sorted(pages, key=lambda p: p.page_index)
        for i, page_opt in enumerate(sorted_pages):
            image = _prepare_page_image(doc, page_opt, dpi)
            words = ocr.run_ocr(image, languages)
            mean_conf = ocr.mean_confidence(words)
            results.append(
                PageOCRResult(page_index=page_opt.page_index, words=words, mean_confidence=mean_conf)
            )
            if on_progress:
                on_progress(
                    {
                        "event": "page_progress",
                        "document": input_pdf,
                        "page_index": page_opt.page_index,
                        "total_pages": total,
                        "stage": "ocr",
                    }
                )
    finally:
        doc.close()

    first_pages_words = [r.words for r in sorted(results, key=lambda r: r.page_index)[:2]]
    candidates = metadata.extract_candidates(first_pages_words) if first_pages_words else MetadataCandidates()
    return results, candidates


def finalize(
    input_pdf: str,
    output_basename: str,
    output_dir: str,
    options: FinalizeOptions,
    pages: list[PageOptions],
    on_progress: Optional[ProgressCallback] = None,
) -> dict:
    _require_input_pdf(input_pdf)
    os.makedirs(output_dir, exist_ok=True)

    doc = pdf_io.open_pdf(input_pdf)
    writer = pypdf.PdfWriter()
    all_words_by_page: list[list] = []
    sorted_pages = sorted(pages, key=lambda p: p.page_index)
    total = len(sorted_pages)

    try:
        for i, page_opt in enumerate(sorted_pages):
            image = _prepare_page_image(doc, page_opt, options.dpi)
            if options.bw:
                # Only the output image is binarized — OCR (ocr_document,
                # above) always runs against the original grayscale/color
                # rasterization, since Tesseract's own adaptive
                # binarization outperforms a single global Otsu threshold.
                image = pdf_io.to_bw(image)
            page_pdf_bytes = textlayer.build_page_pdf(image, page_opt.words, dpi=options.dpi)
            reader = pypdf.PdfReader(io.BytesIO(page_pdf_bytes))
            writer.append(reader)
            all_words_by_page.append(page_opt.words)
            if on_progress:
                on_progress(
                    {
                        "event": "page_progress",
                        "document": input_pdf,
                        "page_index": page_opt.page_index,
                        "total_pages": total,
                        "stage": "finalize",
                    }
                )
    finally:
        doc.close()

    outputs = {"searchable_pdf": None, "plain_text": None, "pdf_a": None}
    needs_base_pdf = options.searchable_pdf or options.pdf_a
    base_pdf_path = os.path.join(output_dir, f"{output_basename}.pdf")

    if needs_base_pdf:
        with open(base_pdf_path, "wb") as f:
            writer.write(f)
    if options.searchable_pdf:
        outputs["searchable_pdf"] = base_pdf_path

    if options.plain_text:
        text_path = os.path.join(output_dir, f"{output_basename}.txt")
        export.write_plain_text(all_words_by_page, text_path)
        outputs["plain_text"] = text_path

    if options.pdf_a:
        pdfa_path = os.path.join(output_dir, f"{output_basename} (PDF-A).pdf")
        export.make_pdf_a_leaning(base_pdf_path, pdfa_path, title=output_basename)
        outputs["pdf_a"] = pdfa_path
        if not options.searchable_pdf:
            os.remove(base_pdf_path)  # was only a temp intermediate for the PDF/A pass

    return outputs


def batch_process(
    documents: list[dict],
    languages: list[str],
    options: FinalizeOptions,
    on_progress: Optional[ProgressCallback] = None,
) -> list[dict]:
    """Runs analyze -> ocr -> finalize per document using only auto-detected
    crop/deskew values (no manual review step — batch mode is unattended).
    """
    results = []
    total_documents = len(documents)

    for doc_idx, doc_spec in enumerate(documents):
        input_pdf = doc_spec["input_pdf"]
        output_dir = doc_spec["output_dir"]
        auto_rename = bool(doc_spec.get("auto_rename", False))

        if on_progress:
            on_progress(
                {
                    "event": "document_progress",
                    "document": input_pdf,
                    "index": doc_idx,
                    "total_documents": total_documents,
                }
            )

        work_dir = tempfile.mkdtemp(prefix="classics_pdf_batch_")
        try:
            analyze_options = AnalyzeOptions(dpi=options.dpi, deskew=True, auto_crop=True)
            pages_analysis = analyze(input_pdf, work_dir, analyze_options, on_progress=on_progress)

            page_options = [
                PageOptions(
                    page_index=p.page_index,
                    crop_box=p.detected_crop_box,
                    deskew_angle_deg=p.skew_angle_deg,
                )
                for p in pages_analysis
            ]

            ocr_results, candidates = ocr_document(
                input_pdf, languages, options.dpi, page_options, on_progress=on_progress
            )
            words_by_index = {r.page_index: r.words for r in ocr_results}
            for page_opt in page_options:
                page_opt.words = words_by_index.get(page_opt.page_index, [])

            if auto_rename:
                basename = metadata.render_filename(
                    candidates.author[0] if candidates.author else None,
                    candidates.title[0] if candidates.title else None,
                    candidates.year[0] if candidates.year else None,
                )
            else:
                basename = os.path.splitext(os.path.basename(input_pdf))[0]

            outputs = finalize(
                input_pdf, basename, output_dir, options, page_options, on_progress=on_progress
            )
            # Aggregate per-page mean_confidence into one document-level figure —
            # batch mode has no interactive review step, so this is the only
            # signal the caller gets for "does this document need a closer look."
            page_confidences = [r.mean_confidence for r in ocr_results if r.mean_confidence >= 0]
            document_confidence = sum(page_confidences) / len(page_confidences) if page_confidences else -1.0
            results.append(
                {
                    "input_pdf": input_pdf,
                    "status": "ok",
                    "outputs": outputs,
                    "mean_confidence": document_confidence,
                }
            )
        except Exception as exc:  # noqa: BLE001 - a per-document failure must not abort the batch
            results.append({"input_pdf": input_pdf, "status": "error", "error": str(exc)})
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)

    return results


def run_command(request: dict, on_progress: Optional[ProgressCallback] = None) -> dict:
    """Top-level dispatch used by cli.py: one request in, one response dict out."""
    command = request.get("command")
    try:
        if command == "analyze":
            options = AnalyzeOptions.from_dict(request.get("options", {}))
            pages = analyze(request["input_pdf"], request["work_dir"], options, on_progress)
            return ok_response(pages=[p.to_dict() for p in pages])

        if command == "ocr":
            options = AnalyzeOptions.from_dict(request.get("options", {}))
            page_options = [PageOptions.from_dict(p) for p in request.get("pages", [])]
            results, candidates = ocr_document(
                request["input_pdf"], request["languages"], options.dpi, page_options, on_progress
            )
            return ok_response(
                pages=[r.to_dict() for r in results],
                metadata_candidates=candidates.to_dict(),
            )

        if command == "finalize":
            options = FinalizeOptions.from_dict(request.get("options", {}))
            page_options = [PageOptions.from_dict(p) for p in request.get("pages", [])]
            outputs = finalize(
                request["input_pdf"],
                request["output_basename"],
                request["output_dir"],
                options,
                page_options,
                on_progress,
            )
            return ok_response(outputs=outputs)

        if command == "batch":
            options = FinalizeOptions.from_dict(request.get("options", {}))
            docs = batch_process(
                request["documents"], request["languages"], options, on_progress
            )
            return ok_response(documents=docs)

        return error_response(f"unknown command: {command!r}")
    except FileNotFoundError as exc:
        return error_response(str(exc))
    except KeyError as exc:
        return error_response(f"missing required field: {exc}")
