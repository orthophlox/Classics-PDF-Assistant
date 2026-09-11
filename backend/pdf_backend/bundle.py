"""Runtime wiring for a PyInstaller-frozen bundle (see packaging/pyinstaller.spec
and packaging/build_backend.sh). No-op during normal execution — this
sandbox's test suite, `cli.py`'s dev-mode invocation, and an Xcode dev build
using BackendLocator's devInvocation() fallback all run pdf_backend as
plain, unfrozen Python and rely on a system Tesseract install instead.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytesseract


def configure_bundled_tesseract() -> None:
    """Point pytesseract at the vendored tesseract binary and tessdata
    instead of a system install. Most end users of the packaged macOS app
    won't have Homebrew Tesseract — the whole point of vendoring a binary
    (packaging/build_backend.sh) is for the shipped app to be
    self-contained, and that vendoring is wasted unless something actually
    tells pytesseract to use it instead of searching PATH.
    """
    if not getattr(sys, "frozen", False):
        return

    bundle_dir = Path(getattr(sys, "_MEIPASS", os.path.dirname(sys.executable)))

    bundled_tesseract = bundle_dir / "tesseract"
    if bundled_tesseract.is_file():
        pytesseract.pytesseract.tesseract_cmd = str(bundled_tesseract)

    bundled_tessdata = bundle_dir / "tessdata"
    if bundled_tessdata.is_dir():
        os.environ.setdefault("TESSDATA_PREFIX", str(bundled_tessdata))
