"""Subprocess entry point: `python -m pdf_backend.cli <command> --request -`.

Reads one JSON request from stdin (or a file), writes one JSON response to
stdout, and streams NDJSON progress events to stderr while running — the
exact contract in docs/JSON_PROTOCOL.md that the Swift app's BackendService
speaks, and the same shape used once this package is frozen by PyInstaller.

Also supports a `process` convenience mode (`--input`/`--output` flags) for
manually testing the full analyze->ocr->finalize pipeline on one PDF without
hand-writing a JSON request.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile

from . import pipeline
from .schemas import AnalyzeOptions, FinalizeOptions, PageOptions


def _stderr_progress(event: dict) -> None:
    sys.stderr.write(json.dumps(event) + "\n")
    sys.stderr.flush()


def _run_protocol_command(command: str, args: argparse.Namespace) -> dict:
    if args.request == "-":
        raw = sys.stdin.read()
    else:
        with open(args.request, encoding="utf-8") as f:
            raw = f.read()
    request = json.loads(raw)
    request.setdefault("command", command)
    return pipeline.run_command(request, on_progress=_stderr_progress)


def _run_convenience_process(args: argparse.Namespace) -> dict:
    languages = args.lang.split("+")
    output_dir = os.path.dirname(os.path.abspath(args.output)) or "."
    output_basename = os.path.splitext(os.path.basename(args.output))[0]

    with tempfile.TemporaryDirectory(prefix="classics_pdf_cli_") as work_dir:
        analyze_options = AnalyzeOptions(dpi=args.dpi, deskew=args.deskew, auto_crop=args.crop)
        pages_analysis = pipeline.analyze(args.input, work_dir, analyze_options, _stderr_progress)

        page_options = [
            PageOptions(
                page_index=p.page_index,
                crop_box=p.detected_crop_box if args.crop else None,
                deskew_angle_deg=p.skew_angle_deg if args.deskew else 0.0,
            )
            for p in pages_analysis
        ]

        ocr_results, candidates = pipeline.ocr_document(
            args.input, languages, args.dpi, page_options, _stderr_progress
        )
        words_by_index = {r.page_index: r.words for r in ocr_results}
        for page_opt in page_options:
            page_opt.words = words_by_index.get(page_opt.page_index, [])

        finalize_options = FinalizeOptions(
            dpi=args.dpi,
            searchable_pdf=True,
            plain_text=args.plain_text,
            pdf_a=args.pdf_a,
        )
        outputs = pipeline.finalize(
            args.input, output_basename, output_dir, finalize_options, page_options, _stderr_progress
        )

    return {
        "status": "ok",
        "error": None,
        "outputs": outputs,
        "metadata_candidates": candidates.to_dict(),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m pdf_backend.cli")
    parser.add_argument(
        "command",
        choices=["analyze", "ocr", "finalize", "batch", "process"],
        help="'process' is a convenience full-pipeline mode; the other four match docs/JSON_PROTOCOL.md.",
    )
    parser.add_argument("--request", help="JSON request file path, or '-' for stdin.")

    convenience = parser.add_argument_group("convenience mode (command=process only)")
    convenience.add_argument("--input", help="Input PDF path")
    convenience.add_argument("--output", help="Output PDF path (basename/dir reused for .txt/PDF-A siblings)")
    convenience.add_argument("--lang", default="grc+lat+eng", help="Tesseract language string")
    convenience.add_argument("--dpi", type=int, default=300)
    convenience.add_argument("--deskew", dest="deskew", action="store_true", default=True)
    convenience.add_argument("--no-deskew", dest="deskew", action="store_false")
    convenience.add_argument("--crop", dest="crop", action="store_true", default=True)
    convenience.add_argument("--no-crop", dest="crop", action="store_false")
    convenience.add_argument("--plain-text", action="store_true", default=False)
    convenience.add_argument("--pdf-a", action="store_true", default=False)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "process":
        if not (args.input and args.output):
            parser.error("command 'process' requires --input and --output")
        response = _run_convenience_process(args)
    else:
        if not args.request:
            parser.error(f"command {args.command!r} requires --request")
        response = _run_protocol_command(args.command, args)

    print(json.dumps(response))
    return 0 if response.get("status") == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
