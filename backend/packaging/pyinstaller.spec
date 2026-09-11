# PyInstaller spec for the pdf_backend CLI, bundled into the macOS app.
#
# Run from backend/packaging/: `pyinstaller pyinstaller.spec`
# (via build_backend.sh, invoked from an Xcode "Run Script" build phase).
#
# NOT run or validated in this Linux dev sandbox: bundling a real Tesseract
# binary means resolving its dylib dependencies (leptonica, libpng, etc. via
# `otool -L` / `install_name_tool`), which only makes sense on a real macOS
# build machine. See docs/ARCHITECTURE.md.

import glob
import sys
from pathlib import Path

block_cipher = None

# build_backend.sh's dylib-walking step (otool -L / install_name_tool)
# copies the Homebrew tesseract binary plus every non-system dylib it
# depends on into vendor/, flat, with internal load paths already rewritten
# to @executable_path/<name> — so bundling is just "ship the whole
# directory next to the frozen executable" (dest "." puts each file
# alongside pdf_backend_cli in the onedir output, matching those rewritten
# paths). Empty if build_backend.sh's vendoring step hasn't run yet, e.g. a
# manual `pyinstaller pyinstaller.spec` for local testing of the pure-Python
# parts — that build just won't have a working bundled tesseract.
vendor_binaries = [(path, ".") for path in glob.glob("vendor/*")]

# onedir (not onefile): more reliable for an OpenCV+Tesseract-heavy bundle —
# avoids onefile's per-launch temp-extraction overhead and extra Gatekeeper/
# notarization friction from a self-extracting binary.
a = Analysis(
    ["../pdf_backend/cli.py"],
    pathex=["../"],
    binaries=vendor_binaries,
    datas=[
        ("../pdf_backend/assets", "pdf_backend/assets"),  # DejaVuSans.ttf, sRGB.icc
        ("tessdata", "tessdata"),  # populated by fetch_tessdata.sh before this runs
    ],
    hiddenimports=[
        "pytesseract",
        "PIL._tkinter_finder",  # avoids a PyInstaller Pillow hook false-negative
    ],
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib"],  # not used; keep the bundle smaller
    cipher=block_cipher,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="pdf_backend_cli",
    debug=False,
    strip=False,
    upx=False,  # UPX-compressed dylibs are a common source of macOS codesign/notarization failures
    console=True,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name="pdf_backend_cli",
)
