#!/usr/bin/env bash
# Builds the PyInstaller-frozen pdf_backend_cli bundle for the macOS app,
# including a vendored Tesseract binary + its dylib dependencies and the
# grc/lat/eng tessdata. Intended to run from an Xcode "Run Script" build
# phase, or manually before opening the project in Xcode.
#
# macOS + Homebrew only — this cannot be run or validated in the Linux dev
# sandbox this repository was otherwise built/tested in (see
# docs/ARCHITECTURE.md). The backend's Python logic (deskew/crop/OCR/
# metadata/export) is already tested independently of this script; what
# this script does — resolving Tesseract's dylib graph with otool/
# install_name_tool so it runs from inside an app bundle without a system
# Homebrew install — needs a real Mac to attempt or verify at all.
#
# Usage: ./build_backend.sh

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "build_backend.sh must run on macOS (needs otool/install_name_tool + a Homebrew Tesseract build)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "== 1/4: Python venv + dependencies =="
python3 -m venv "$SCRIPT_DIR/.build_venv"
source "$SCRIPT_DIR/.build_venv/bin/activate"
pip install --upgrade pip
pip install -r "$BACKEND_DIR/requirements.txt"
pip install pyinstaller

echo "== 2/4: tessdata (grc/lat/eng/osd) =="
"$SCRIPT_DIR/fetch_tessdata.sh"

echo "== 3/4: vendor Homebrew Tesseract binary + dylibs =="
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found — install Tesseract (brew install tesseract) first." >&2
  exit 1
fi
TESSERACT_PREFIX="$(brew --prefix tesseract)"
TESSERACT_BIN="$TESSERACT_PREFIX/bin/tesseract"
if [[ ! -x "$TESSERACT_BIN" ]]; then
  echo "tesseract binary not found at $TESSERACT_BIN — run: brew install tesseract" >&2
  exit 1
fi

VENDOR_DIR="$SCRIPT_DIR/vendor"
mkdir -p "$VENDOR_DIR"
cp "$TESSERACT_BIN" "$VENDOR_DIR/tesseract"

# Walk the dylib dependency graph with otool -L, copy each non-system
# (/usr/lib, /System) dependency into VENDOR_DIR, and rewrite the binary's
# and each dylib's load paths with install_name_tool so everything resolves
# via @executable_path/../Frameworks (or wherever the Xcode build phase
# ultimately places this bundle) instead of the Homebrew Cellar path.
# This is inherently iterative (a copied dylib can have its own further
# dependencies) — copy_deps below recurses until nothing new is found.
copy_deps() {
  local binary="$1"
  local deps
  deps="$(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -v '^/usr/lib/' | grep -v '^/System/')"
  for dep in $deps; do
    local base
    base="$(basename "$dep")"
    if [[ ! -f "$VENDOR_DIR/$base" ]]; then
      cp "$dep" "$VENDOR_DIR/$base"
      chmod +w "$VENDOR_DIR/$base"
      install_name_tool -id "@executable_path/$base" "$VENDOR_DIR/$base"
      copy_deps "$VENDOR_DIR/$base"
    fi
    install_name_tool -change "$dep" "@executable_path/$base" "$binary"
  done
}
chmod +w "$VENDOR_DIR/tesseract"
copy_deps "$VENDOR_DIR/tesseract"

echo "== 4/4: PyInstaller =="
pushd "$SCRIPT_DIR" >/dev/null
pyinstaller --noconfirm pyinstaller.spec
popd >/dev/null

echo "Backend bundle ready at $SCRIPT_DIR/dist/pdf_backend_cli"
echo "Copy this directory's contents into the app bundle's Resources (or wherever"
echo "BackendLocator.swift expects it) as part of the Xcode build phase."
